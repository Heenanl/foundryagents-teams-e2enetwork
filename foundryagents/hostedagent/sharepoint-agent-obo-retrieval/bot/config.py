# Copyright (c) Microsoft. All rights reserved.
import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    """Bot configuration from environment variables."""

    PORT = int(os.getenv("PORT", "3978"))

    # Azure Bot registration (SingleTenant). MicrosoftAppId = the bot's Entra app (client) id.
    APP_ID = os.environ.get("MicrosoftAppId", "")
    APP_PASSWORD = os.environ.get("MicrosoftAppPassword", "")
    APP_TENANTID = os.environ.get("MicrosoftAppTenantId", "")
    APP_TYPE = os.environ.get("MicrosoftAppType", "SingleTenant")

    # Azure Bot OAuth connection name. Configure this connection on the bot to return a token with
    # delegated Microsoft Graph scopes Files.Read.All + Sites.Read.All (Teams SSO makes it silent).
    OAUTH_CONNECTION_NAME = os.environ.get("OAUTH_CONNECTION_NAME", "graph")

    # The hosted agent's /responses endpoint (Option C agent).
    AGENT_RESPONSES_ENDPOINT = os.environ.get("AGENT_RESPONSES_ENDPOINT", "")
    STRUCTURED_INPUT_TOKEN_KEY = os.environ.get("STRUCTURED_INPUT_TOKEN_KEY", "userToken")
