from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
import os

# Format: "https://resource_name.services.ai.azure.com/api/projects/project_name"
PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"]

# Create project client to call Foundry API
project = AIProjectClient(
    endpoint=PROJECT_ENDPOINT,
    credential=DefaultAzureCredential(),
)

# Create a prompt agent
agent = project.agents.create_version(
    agent_name="mypromptagententra",
    definition=PromptAgentDefinition(
        model="gpt-5-mini",
        instructions="You are a helpful assistant.",
    ),
)
print(f"Agent: {agent.name}, Version: {agent.version}")