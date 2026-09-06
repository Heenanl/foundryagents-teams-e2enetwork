# Copyright (c) Microsoft. All rights reserved.
"""Provider: whoami. A zero-downstream diagnostic that echoes the identity resolved from the
forwarded user token. Use it to prove the OAuth2 passthrough is delivering a per-user token before
wiring real tools (both the alisoliman/mcp-obo and karpikpl samples ship an equivalent)."""

import base64
import json

from fastmcp.server.dependencies import get_http_headers

name = "whoami"


def _claims() -> dict:
    raw = get_http_headers(include_all=True).get("authorization", "")
    token = raw[7:].strip() if raw.lower().startswith("bearer ") else raw
    if not token or token.count(".") < 2:
        return {}
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(payload))
    except Exception:
        return {}


def register(mcp, exchange) -> None:
    @mcp.tool(name="whoami", description="Return the identity of the signed-in user (from the forwarded token).")
    async def whoami() -> dict:
        c = _claims()
        return {
            "name": c.get("name"),
            "upn": c.get("preferred_username") or c.get("upn"),
            "oid": c.get("oid"),
            "tenant": c.get("tid"),
            "scopes": c.get("scp"),
            "audience": c.get("aud"),
        }
