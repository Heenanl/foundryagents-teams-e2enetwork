# Simple SharePoint grounding agent backed by the Microsoft 365 Copilot Retrieval API.
#
# IMPORTANT — how this tool authenticates:
#   The SharePoint grounding tool (sharepoint_grounding_preview) requires the SIGNED-IN USER's
#   delegated identity (On-Behalf-Of). It does NOT work with a deployed hosted-agent managed
#   identity (app-only is rejected) and is NOT supported when the agent is published to Microsoft
#   Teams. Run this as the user: `az login` as that user, then `python sharepoint_agent.py`.
#   (This mirrors the "Hosted Agents" pivot in the Foundry SharePoint tool docs, which is an
#   in-process Agent Framework agent run under the user's identity.)
#
# Licensing: the user needs a Microsoft 365 Copilot license OR the tenant must have the Retrieval
#   API pay-as-you-go model enabled (SharePoint is a tenant-level source, so pay-as-you-go covers it).

import asyncio
import os

from agent_framework import Agent
from agent_framework.foundry import FoundryChatClient
from azure.ai.projects import AIProjectClient
from azure.identity import AzureCliCredential
from dotenv import load_dotenv

load_dotenv()


async def main() -> None:
    # AzureCliCredential resolves to the `az login` user so SharePoint applies THAT user's
    # permissions. Do not use a managed identity / service principal here.
    credential = AzureCliCredential()

    project_endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
    connection_name = os.environ["SHAREPOINT_CONNECTION_NAME"]

    project = AIProjectClient(endpoint=project_endpoint, credential=credential)
    sharepoint_connection_id = project.connections.get(connection_name).id

    agent = Agent(
        client=FoundryChatClient(
            project_endpoint=project_endpoint,
            model=os.environ.get("FOUNDRY_MODEL", "gpt-4.1-mini"),
            credential=credential,
        ),
        instructions=(
            "You are a helpful assistant for internal company knowledge. Use the SharePoint tool "
            "to retrieve and answer from documents the signed-in user is permitted to see, and "
            "cite the source documents. Only return what that user can access."
        ),
        # .as_dict() works around an SDK bug: get_sharepoint_tool() returns a SharepointPreviewTool
        # whose nested SharepointGroundingToolParameters isn't JSON-serializable by the openai client
        # ("Object of type SharepointGroundingToolParameters is not JSON serializable").
        tools=[FoundryChatClient.get_sharepoint_tool(connection_id=sharepoint_connection_id).as_dict()],
    )

    query = os.environ.get("QUERY", "Summarize the latest document in the SharePoint site.")
    result = await agent.run(query)

    print(f"\nAgent: {result.text}\n")
    for message in result.messages:
        for content in message.contents:
            for annotation in getattr(content, "annotations", None) or []:
                url = getattr(annotation, "url", None)
                if url:
                    title = getattr(annotation, "title", None) or ""
                    print(f"Citation: [{title}]({url})")


if __name__ == "__main__":
    asyncio.run(main())
