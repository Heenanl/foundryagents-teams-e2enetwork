# Copyright (c) Microsoft. All rights reserved.
"""
Hosted Foundry agent that grounds on **one SharePoint site**, per user, by calling the
**Microsoft 365 Copilot Retrieval API** with a user token passed in via `structured_inputs`.

Why this exists: the built-in SharePoint grounding tool can't run from a hosted container
(app-only is rejected), and Work IQ can't scope to a single site. This agent does both:

    caller (Bot/Teams SSO) --> structured_inputs.userToken (a Graph token, Files.Read.All +
    Sites.Read.All) --> this container reads it --> POST /copilot/retrieval with a site-scoped
    KQL filterExpression --> permission-trimmed, single-site results --> model answers with citations.

The container authenticates to the Foundry *model* with its managed identity (that call doesn't
need the user). Only the **retrieval** uses the user's token, so answers stay permission-trimmed.

Token: pass a **Graph** access token (audience https://graph.microsoft.com, scopes Files.Read.All
and Sites.Read.All) as `structured_inputs.userToken`. The bot obtains it via Teams SSO + OBO. If you
prefer the container to do the OBO exchange itself, see `_maybe_obo()` below (needs a confidential
client app + secret; off by default to keep the container secret-free).
"""

import json
import logging
import os

import httpx
from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

TOKEN_KEY = os.getenv("STRUCTURED_INPUT_TOKEN_KEY", "userToken")
RETRIEVAL_URL = os.getenv("RETRIEVAL_API_URL", "https://graph.microsoft.com/v1.0/copilot/retrieval")
SITE_URL = os.getenv("SHAREPOINT_SITE_URL", "").rstrip("/")
MAX_RESULTS = int(os.getenv("MAX_RESULTS", "10"))


def _extract_question(items) -> str:
    """Concatenate the user's input text from responses input items (dicts or typed objects)."""
    parts: list[str] = []
    for item in items or []:
        content = item.get("content") if isinstance(item, dict) else getattr(item, "content", None)
        for block in content or []:
            btype = block.get("type") if isinstance(block, dict) else getattr(block, "type", None)
            if btype in ("input_text", "text", "output_text"):
                text = block.get("text") if isinstance(block, dict) else getattr(block, "text", None)
                if text:
                    parts.append(text)
    return "\n".join(parts).strip()


def _format_grounding(hits: list[dict]) -> tuple[str, list[tuple[str, str]]]:
    lines: list[str] = []
    citations: list[tuple[str, str]] = []
    for hit in hits:
        url = hit.get("webUrl")
        meta = hit.get("resourceMetadata") or {}
        title = meta.get("title") or url or "source"
        for extract in hit.get("extracts", []):
            text = extract.get("text")
            if text:
                lines.append(f"[{title}] {text}")
        if url:
            citations.append((title, url))
    return "\n".join(lines), citations


async def _retrieve(user_token: str, question: str) -> list[dict]:
    """Call the Retrieval API on behalf of the user, scoped to one SharePoint site."""
    body: dict = {
        "queryString": (question or "")[:1500] or "Summarize the most relevant document.",
        "dataSource": "sharePoint",
        "resourceMetadata": ["title", "author"],
        "maximumNumberOfResults": MAX_RESULTS,
    }
    if SITE_URL:
        # KQL path filter pins retrieval to a single site (kills cross-source noise).
        body["filterExpression"] = f'path:"{SITE_URL}/"'
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            RETRIEVAL_URL,
            headers={"Authorization": f"Bearer {user_token}", "Content-Type": "application/json"},
            json=body,
        )
    resp.raise_for_status()
    return resp.json().get("retrievalHits", [])


class _RetrievalGroundingServer(ResponsesHostServer):
    """Per request: read the user token from structured_inputs, retrieve site-scoped extracts,
    and hand the model a grounded prompt so it answers with citations."""

    async def _handle_inner_agent(self, *args, **kwargs):  # type: ignore[override]
        request = next((a for a in (*args, *kwargs.values()) if isinstance(a, dict)), None)
        context = next((a for a in (*args, *kwargs.values()) if hasattr(a, "get_input_items")), None)

        structured = (request or {}).get("structured_inputs") or {}
        raw_token = str(structured.get(TOKEN_KEY, "")).strip()
        user_token = raw_token[7:].strip() if raw_token.lower().startswith("bearer ") else raw_token

        question = _extract_question(await context.get_input_items()) if context is not None else ""

        if not user_token:
            grounding = (
                "NO_USER_TOKEN: the caller did not pass a user token in "
                f"structured_inputs['{TOKEN_KEY}'], so SharePoint could not be queried."
            )
            citations: list[tuple[str, str]] = []
        else:
            try:
                hits = await _retrieve(user_token, question)
                grounding, citations = _format_grounding(hits)
                if not grounding:
                    grounding = "NO_RESULTS: the retrieval returned no extracts the user can access."
            except httpx.HTTPStatusError as ex:  # e.g. 403 license / permissions
                body = ex.response.text[:400]
                grounding = f"RETRIEVAL_ERROR {ex.response.status_code}: {body}"
                citations = []
            except Exception as ex:  # noqa: BLE001
                grounding = f"RETRIEVAL_ERROR: {ex!r}"
                citations = []

        cite_block = "\n".join(f"- [{t}]({u})" for t, u in citations) or "(none)"
        grounded_input = (
            "Answer the user's question using ONLY the SharePoint extracts below. "
            "Cite the source URLs you rely on. If the extracts don't contain the answer, say so.\n\n"
            f"=== SharePoint extracts (single-site, permission-trimmed) ===\n{grounding}\n\n"
            f"=== Candidate citations ===\n{cite_block}\n\n"
            f"=== User question ===\n{question or '(no question provided)'}"
        )

        if context is not None:
            async def _synth(*_a, **_k):
                return [{"type": "message", "role": "user",
                         "content": [{"type": "input_text", "text": grounded_input}]}]
            try:
                context.get_input_items = _synth  # type: ignore[method-assign]
            except Exception:  # noqa: BLE001
                pass

        async for event in super()._handle_inner_agent(*args, **kwargs):
            yield event


def main():
    try:
        from azure.ai.agentserver.core.tasks import set_resilient_tasks_enabled

        set_resilient_tasks_enabled(True)
    except Exception:  # noqa: BLE001
        logger.warning("Could not enable resilient tasks", exc_info=True)

    if not SITE_URL:
        logger.warning("SHAREPOINT_SITE_URL is not set — retrieval will NOT be site-scoped.")

    # Managed identity authenticates the container's calls to the Foundry *model* only.
    credential = DefaultAzureCredential()
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=credential,
    )
    agent = Agent(
        client=client,
        instructions=(
            "You are an internal knowledge assistant grounded on a single SharePoint site. "
            "Use only the provided extracts, answer concisely, and include source citations."
        ),
        default_options={"store": False},
    )
    server = _RetrievalGroundingServer(agent)
    server.run()


if __name__ == "__main__":
    main()
