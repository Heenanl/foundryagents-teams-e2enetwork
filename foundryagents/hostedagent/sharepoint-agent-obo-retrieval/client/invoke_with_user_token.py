# Copyright (c) Microsoft. All rights reserved.
"""
Reference client: acquire the user's Graph token and invoke the hosted agent, passing the token
through `structured_inputs`. In production this logic lives in your **Teams bot** (Teams SSO + OBO);
this script is the local stand-in so you can test the agent without Teams.

Two tokens are involved:
  1. AI token  (audience https://ai.azure.com)      -> authenticates the call to the agent endpoint.
  2. User Graph token (Files.Read.All, Sites.Read.All) -> passed in structured_inputs; the agent uses
     it to call the Retrieval API on the user's behalf (permission-trimmed, site-scoped).

Env:
  AGENT_RESPONSES_ENDPOINT  https://<account>.services.ai.azure.com/api/projects/<project>/agents/agent-framework-agent-sharepoint-obo/endpoint/protocols/openai/responses?api-version=v1
  ENTRA_CLIENT_ID           app (client) ID with delegated Files.Read.All + Sites.Read.All granted
  ENTRA_TENANT_ID           your tenant ID
  QUERY                     the question to ask
"""

import os

import httpx
from azure.identity import InteractiveBrowserCredential
from dotenv import load_dotenv

load_dotenv()

GRAPH_SCOPES = ["https://graph.microsoft.com/Files.Read.All", "https://graph.microsoft.com/Sites.Read.All"]
AI_SCOPE = "https://ai.azure.com/.default"


def main() -> None:
    endpoint = os.environ["AGENT_RESPONSES_ENDPOINT"]
    query = os.environ.get("QUERY", "Summarize the most relevant document on the site.")

    # A real bot gets these via Teams SSO + OBO. Locally we sign the user in interactively.
    cred = InteractiveBrowserCredential(
        tenant_id=os.environ["ENTRA_TENANT_ID"],
        client_id=os.environ["ENTRA_CLIENT_ID"],
    )
    user_graph_token = cred.get_token(*GRAPH_SCOPES).token   # forwarded to the agent (per-user)
    ai_token = cred.get_token(AI_SCOPE).token                # authenticates the agent call

    body = {
        "input": query,
        "store": False,
        "structured_inputs": {"userToken": f"Bearer {user_graph_token}"},
    }

    resp = httpx.post(
        endpoint,
        headers={"Authorization": f"Bearer {ai_token}", "Content-Type": "application/json"},
        json=body,
        timeout=120.0,
    )
    print(f"HTTP {resp.status_code}")
    print(resp.text)


if __name__ == "__main__":
    main()
