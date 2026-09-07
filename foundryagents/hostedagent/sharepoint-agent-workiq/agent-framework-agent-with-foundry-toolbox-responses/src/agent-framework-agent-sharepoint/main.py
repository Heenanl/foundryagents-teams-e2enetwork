# Copyright (c) Microsoft. All rights reserved.

import httpx
import json
import logging
import os

from agent_framework import Agent, MCPStreamableHTTPTool
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

logger = logging.getLogger(__name__)


def is_toolbox_enabled() -> bool:
    """Return whether the Work IQ / SharePoint toolbox integration is enabled."""
    value = os.getenv("ENABLE_TOOLBOX", "true").strip().lower()
    return value not in {"0", "false", "no", "off"}


def _install_a2a_preview_consent_patch() -> None:
    """Backport agent-framework PR #7606 so Work IQ 'a2a_preview' consent errors
    are surfaced as the SDK's friendly `oauth_consent_request` card.

    Older `agent_framework_foundry_hosting` builds only recognized consent errors
    of type 'mcp'; Work IQ tools report type 'a2a_preview', so the host fell back
    to a raw `response.failed` (ugly blob in Teams). We replace the module-level
    `consent_url_from_error` with a version that also recognizes 'a2a_preview'.
    Harmless no-op on newer SDK builds that already include the fix.
    """
    try:
        from agent_framework_foundry_hosting import _responses as responses_mod
        from mcp import McpError
    except Exception:  # noqa: BLE001 - best-effort; leave SDK default in place
        logger.warning("Could not install a2a_preview consent patch", exc_info=True)
        return

    consent_error_cls = responses_mod.ConsentError
    consent_error_code = responses_mod.CONSENT_ERROR_CODE

    def consent_url_from_error(exc):
        inner = next((a for a in exc.args if isinstance(a, McpError)), None)
        if inner is None or inner.error.code != consent_error_code:
            return None
        message = inner.error.message
        start = message.find("{")
        if start == -1:
            return None
        try:
            details = json.loads(message[start:])
        except json.JSONDecodeError:
            return None
        errors = details.get("errors")
        if not isinstance(errors, list):
            return None
        found = []
        for err in errors:
            if (
                isinstance(err, dict)
                and err.get("type") in ("mcp", "a2a_preview")
                and isinstance(err.get("error"), dict)
                and err["error"].get("code") == "CONSENT_REQUIRED"
                and isinstance(err["error"].get("message"), str)
            ):
                found.append(
                    consent_error_cls(name=err.get("name", "Unknown"), consent_url=err["error"]["message"])
                )
        return found or None

    responses_mod.consent_url_from_error = consent_url_from_error
    logger.info("Installed a2a_preview consent recognition patch.")


class _ResilientResponsesHostServer(ResponsesHostServer):
    """Hardens the responses host against two issues.

    1. The built-in `_handle_inner_agent` calls `await context.get_history()`
       unconditionally; when the platform issues a `store=true` request with a
       real `conversation.id`, that fetch can raise inside the SDK and bubble up
       as a `server_error`. We wrap `get_history` so a transient failure degrades
       to "no prior turns".
    2. Work IQ first-run consent is surfaced natively by the SDK as an
       `oauth_consent_request` card (see `_install_a2a_preview_consent_patch`),
       so no consent handling is needed here.
    """

    async def _handle_inner_agent(self, request, context):  # type: ignore[override]
        original_get_history = context.get_history

        async def safe_get_history():
            try:
                return await original_get_history()
            except Exception as ex:  # noqa: BLE001 - intentional broad catch
                logger.warning(
                    "context.get_history() failed (%s); proceeding with no prior history.",
                    ex,
                )
                return []

        # Replace the bound method on the instance for the duration of this request.
        context.get_history = safe_get_history  # type: ignore[method-assign]
        async for item in super()._handle_inner_agent(request, context):
            yield item


def resolve_toolbox_endpoint() -> str:
    """Resolve the toolbox MCP consumer endpoint URL (always the default version)."""
    project_endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"].rstrip("/")
    toolbox_name = os.environ["TOOLBOX_NAME"]
    return f"{project_endpoint}/toolboxes/{toolbox_name}/mcp?api-version=v1"


class ToolboxAuth(httpx.Auth):
    """Injects a fresh agent-identity bearer token on every toolbox request."""

    def __init__(self, token_provider):
        self._get_token = token_provider

    def auth_flow(self, request):
        request.headers["Authorization"] = f"Bearer {self._get_token()}"
        yield request


def main():
    # The deployed responses SDK requires the resilient-task subsystem to be
    # enabled for store=true requests (the platform issues these). Without it the
    # host fails every /responses call with "Resilient task subsystem missing".
    try:
        from azure.ai.agentserver.core.tasks import set_resilient_tasks_enabled

        set_resilient_tasks_enabled(True)
    except Exception:  # noqa: BLE001 - best-effort; log and continue
        logger.warning("Could not enable resilient tasks", exc_info=True)

    # Make Work IQ (a2a_preview) first-run consent render as the native sign-in card.
    _install_a2a_preview_consent_patch()

    # The MCPStreamableHTTPTool context is entered lazily on the first request
    # (not at startup): the foundry-ext deploy path probes /readiness within
    # ~90s of container start, and eagerly doing the MCP initialize + tools/list
    # against the toolbox endpoint can lose that readiness race (424
    # session_not_ready). Building the Agent without entering the tool context
    # keeps startup fast.
    credential = DefaultAzureCredential()

    # Agent-to-toolbox identity: the agent's own credential, scoped to the platform.
    # Per-user SharePoint/Work IQ identity is supplied server-side by Foundry.
    token_provider = get_bearer_token_provider(
        credential,
        "https://ai.azure.com/.default",
    )

    http_client = httpx.AsyncClient(
        auth=ToolboxAuth(token_provider),
        timeout=120.0,
    )

    toolbox = MCPStreamableHTTPTool(
        name=os.environ["TOOLBOX_NAME"],
        url=resolve_toolbox_endpoint(),
        http_client=http_client,
        load_prompts=False,
    )

    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )

    agent = Agent(
        client=client,
        instructions=(
            "You are a helpful assistant for internal company knowledge. "
            "When the user asks about documents, files, policies, or content that "
            "lives in SharePoint or OneDrive, use the available Work IQ tools to "
            "retrieve and cite that content. The tools run on behalf of the signed-in "
            "user, so only return what that user is permitted to see. Keep answers brief "
            "and include document citations when available."
        ),
        tools=toolbox if is_toolbox_enabled() else None,
        # History is managed by the hosting infrastructure; we don't need
        # the service to store it.
        default_options={"store": False},
    )

    server = _ResilientResponsesHostServer(agent)
    server.run()


if __name__ == "__main__":
    main()
