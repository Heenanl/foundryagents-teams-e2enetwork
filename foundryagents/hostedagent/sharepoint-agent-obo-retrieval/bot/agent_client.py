# Copyright (c) Microsoft. All rights reserved.
"""Calls the Foundry hosted agent's /responses endpoint, passing the user's token via
structured_inputs. This is the piece that carries the per-user identity into the hosted agent."""

import os

import httpx
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

AI_SCOPE = "https://ai.azure.com/.default"


class AgentClient:
    def __init__(self, responses_endpoint: str, token_key: str = "userToken"):
        self._endpoint = responses_endpoint
        self._token_key = token_key
        # The bot authenticates to Foundry with ITS OWN identity (managed identity / the app the
        # bot runs as). The user's identity travels in the body via structured_inputs — not here.
        self._ai_token = get_bearer_token_provider(DefaultAzureCredential(), AI_SCOPE)

    async def ask(self, question: str, user_graph_token: str) -> dict:
        """Send the question + the user's Graph token; return the parsed responses payload."""
        body = {
            "input": question,
            "store": False,
            "structured_inputs": {self._token_key: f"Bearer {user_graph_token}"},
        }
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                self._endpoint,
                headers={
                    "Authorization": f"Bearer {self._ai_token()}",
                    "Content-Type": "application/json",
                },
                json=body,
            )
        resp.raise_for_status()
        return resp.json()

    @staticmethod
    def extract_text(payload: dict) -> str:
        """Pull the assistant's text (and any citations) out of a responses payload."""
        if payload.get("output_text"):
            return payload["output_text"]
        for item in payload.get("output", []):
            if item.get("type") == "message":
                for block in item.get("content", []):
                    if block.get("type") == "output_text":
                        return block.get("text", "")
        if payload.get("error"):
            return f"Agent error: {payload['error'].get('message', payload['error'])}"
        return "(no answer)"


def agent_client_from_env() -> AgentClient:
    return AgentClient(
        responses_endpoint=os.environ["AGENT_RESPONSES_ENDPOINT"],
        token_key=os.getenv("STRUCTURED_INPUT_TOKEN_KEY", "userToken"),
    )
