# Copyright (c) Microsoft. All rights reserved.
"""Generic MCP OBO gateway.

Foundry connects to this MCP server via an OAuth2 identity-passthrough connection and forwards the
signed-in user's token as the request's Authorization header (the same mechanism Work IQ / Databricks
Genie use — so it works from a HOSTED agent published to Teams via the Foundry auto-bot, no custom
Teams bot). For each MCP tool call, the gateway does an On-Behalf-Of exchange to the scopes the tool
needs, then the provider calls the downstream API as the user.

Add support for a new downstream tool (that lacks Foundry server-side OBO) by dropping a new module
in providers/ — the OBO + MCP transport here is generic.
"""

import logging

from fastmcp import FastMCP
from fastmcp.server.dependencies import get_http_headers

import providers as provider_loader
from config import Config
from obo import Obo

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mcp-obo-gateway")

CONFIG = Config()


def _build_auth():
    """Verify the inbound bearer token (audience/issuer/scope) before any tool runs, and publish
    RFC 9728 protected-resource metadata so MCP clients can discover the auth server. Learned from
    the alisoliman/mcp-obo and karpikpl passthrough samples, which both verify rather than trust."""
    if not CONFIG.VERIFY_TOKENS:
        logger.warning("VERIFY_TOKENS=false \u2014 inbound tokens are NOT validated (local testing only)")
        return None
    from fastmcp.server.auth import RemoteAuthProvider
    from fastmcp.server.auth.providers.azure import AzureJWTVerifier
    from pydantic import AnyHttpUrl

    verifier = AzureJWTVerifier(
        client_id=CONFIG.CLIENT_ID,
        tenant_id=CONFIG.TENANT_ID,
        required_scopes=CONFIG.REQUIRED_SCOPES,
    )
    return RemoteAuthProvider(
        token_verifier=verifier,
        authorization_servers=[AnyHttpUrl(f"https://login.microsoftonline.com/{CONFIG.TENANT_ID}/v2.0")],
        base_url=CONFIG.SERVER_URL or f"http://localhost:{CONFIG.PORT}",
    )


mcp = FastMCP("obo-gateway", auth=_build_auth(), mask_error_details=True)
_obo = Obo(
    CONFIG.TENANT_ID,
    CONFIG.CLIENT_ID,
    CONFIG.CLIENT_SECRET,
    CONFIG.MANAGED_IDENTITY_CLIENT_ID,
)


async def exchange(scopes: list[str]) -> str:
    """OBO the CURRENT request's user token to `scopes`. Providers call this; they never see auth."""
    headers = get_http_headers(include_all=True)
    raw = headers.get("authorization", "")
    user_token = raw[7:].strip() if raw.lower().startswith("bearer ") else raw
    if not user_token:
        raise RuntimeError(
            "No user token on the request. Configure the Foundry connection as OAuth2 "
            "identity-passthrough so Foundry forwards the user token to this MCP server."
        )
    return await _obo.exchange(user_token, scopes)


for module in provider_loader.load(CONFIG.ENABLED_PROVIDERS):
    module.register(mcp, exchange)
    logger.info("Registered provider: %s", getattr(module, "name", module.__name__))


if __name__ == "__main__":
    # Streamable HTTP MCP endpoint at /mcp/ (point the Foundry MCP connection here).
    mcp.run(transport="http", host="0.0.0.0", port=CONFIG.PORT)
