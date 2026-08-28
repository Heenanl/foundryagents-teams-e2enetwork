# Copyright (c) Microsoft. All rights reserved.
"""aiohttp host for the Teams SSO bot."""

import sys
import traceback
from datetime import datetime

from aiohttp import web
from aiohttp.web import Request, Response, json_response
from botbuilder.core import ConversationState, MemoryStorage, TurnContext, UserState
from botbuilder.core.integration import aiohttp_error_middleware
from botbuilder.integration.aiohttp import CloudAdapter, ConfigurationBotFrameworkAuthentication
from botbuilder.schema import Activity, ActivityTypes

from agent_client import agent_client_from_env
from bot import TeamsSsoBot
from config import Config
from dialogs import MainDialog

CONFIG = Config()

ADAPTER = CloudAdapter(ConfigurationBotFrameworkAuthentication(CONFIG))


async def on_error(context: TurnContext, error: Exception):
    print(f"\n [on_turn_error] unhandled error: {error}", file=sys.stderr)
    traceback.print_exc()
    await context.send_activity("The bot hit an error. Please try again.")


ADAPTER.on_turn_error = on_error

MEMORY = MemoryStorage()
CONVERSATION_STATE = ConversationState(MEMORY)
USER_STATE = UserState(MEMORY)

DIALOG = MainDialog(CONFIG.OAUTH_CONNECTION_NAME, agent_client_from_env())
BOT = TeamsSsoBot(CONVERSATION_STATE, USER_STATE, DIALOG)


async def messages(req: Request) -> Response:
    if "application/json" not in req.headers.get("Content-Type", ""):
        return Response(status=415)
    body = await req.json()
    activity = Activity().deserialize(body)
    auth_header = req.headers.get("Authorization", "")
    response = await ADAPTER.process_activity(auth_header, activity, BOT.on_turn)
    if response:
        return json_response(data=response.body, status=response.status)
    return Response(status=201)


async def health(_req: Request) -> Response:
    return json_response({"status": "ok", "time": datetime.utcnow().isoformat()})


APP = web.Application(middlewares=[aiohttp_error_middleware])
APP.router.add_post("/api/messages", messages)
APP.router.add_get("/healthz", health)


if __name__ == "__main__":
    web.run_app(APP, host="0.0.0.0", port=CONFIG.PORT)
