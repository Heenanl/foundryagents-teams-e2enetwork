# Copyright (c) Microsoft. All rights reserved.
"""Browser-free end-to-end validation of the MCP-OBO gateway.

Acquires a REAL delegated user token for the gateway's `access_as_user` scope via the Azure CLI
(which the gateway app pre-authorizes), then drives the gateway exactly as Foundry's OAuth2
passthrough would: sends the token as Authorization, calls `whoami`, then `sharepoint_retrieve`.

Expected result once admin consent is granted: whoami returns the signed-in user; sharepoint_retrieve
does OBO -> Graph and calls the Retrieval API, which returns 403 ONLY because of the M365 Copilot
license (the known, out-of-scope hurdle). Everything up to that point proves the chain works.
"""

import asyncio
import os
import subprocess
import sys

from fastmcp import Client
from fastmcp.client.transports import StreamableHttpTransport


def _user_token(app_id: str) -> str:
    for args in (
        ["az", "account", "get-access-token", "--scope", f"api://{app_id}/access_as_user",
         "--query", "accessToken", "-o", "tsv"],
        ["az", "account", "get-access-token", "--resource", f"api://{app_id}",
         "--query", "accessToken", "-o", "tsv"],
    ):
        r = subprocess.run(args, capture_output=True, text=True, shell=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    print("Failed to get a user token via az:", r.stderr, file=sys.stderr)
    sys.exit(1)


async def main() -> None:
    app_id = os.environ["GATEWAY_CLIENT_ID"]
    url = os.environ.get("GATEWAY_URL", "http://localhost:8000/mcp/")
    token = _user_token(app_id)

    transport = StreamableHttpTransport(url, headers={"Authorization": f"Bearer {token}"})
    async with Client(transport) as c:
        tools = [t.name for t in await c.list_tools()]
        print("tools:", tools)

        who = await c.call_tool("whoami", {})
        print("whoami:", who.data)

        try:
            res = await c.call_tool("sharepoint_retrieve", {"query": "What is in this site?"})
            print("sharepoint_retrieve:", res.data)
        except Exception as e:  # noqa: BLE001 - surface the exact downstream failure
            print("sharepoint_retrieve error:", e)


if __name__ == "__main__":
    asyncio.run(main())
