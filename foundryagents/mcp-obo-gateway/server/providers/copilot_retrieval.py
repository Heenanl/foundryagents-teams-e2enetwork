# Copyright (c) Microsoft. All rights reserved.
"""Provider: Microsoft 365 Copilot Retrieval API (SharePoint), per-user, site-scoped.

This is the reference provider. To support a different downstream tool that lacks Foundry
server-side OBO, copy this file, change GRAPH_SCOPES + the HTTP call, and register it."""

import os

import httpx

GRAPH_SCOPES = ["https://graph.microsoft.com/Files.Read.All", "https://graph.microsoft.com/Sites.Read.All"]
RETRIEVAL_URL = os.getenv("RETRIEVAL_API_URL", "https://graph.microsoft.com/v1.0/copilot/retrieval")
SITE_URL = os.getenv("SHAREPOINT_SITE_URL", "").rstrip("/")
MAX_RESULTS = int(os.getenv("MAX_RESULTS", "10"))

name = "copilot_retrieval"


def register(mcp, exchange) -> None:
    @mcp.tool(
        name="sharepoint_retrieve",
        description=(
            "Retrieve relevant text extracts from the configured SharePoint site, on behalf of the "
            "signed-in user (permission-trimmed). Input: a natural-language question."
        ),
    )
    async def sharepoint_retrieve(query: str) -> dict:
        graph_token = await exchange(GRAPH_SCOPES)  # OBO -> Graph, done by the gateway
        body: dict = {
            "queryString": (query or "")[:1500] or "Summarize the most relevant document.",
            "dataSource": "sharePoint",
            "resourceMetadata": ["title", "author"],
            "maximumNumberOfResults": MAX_RESULTS,
        }
        if SITE_URL:
            body["filterExpression"] = f'path:"{SITE_URL}/"'  # scope to ONE site
        async with httpx.AsyncClient(timeout=60.0) as client:
            resp = await client.post(
                RETRIEVAL_URL,
                headers={"Authorization": f"Bearer {graph_token}", "Content-Type": "application/json"},
                json=body,
            )
        resp.raise_for_status()
        hits = resp.json().get("retrievalHits", [])
        return {
            "results": [
                {
                    "webUrl": h.get("webUrl"),
                    "title": (h.get("resourceMetadata") or {}).get("title"),
                    "extracts": [e.get("text") for e in h.get("extracts", []) if e.get("text")],
                }
                for h in hits
            ]
        }
