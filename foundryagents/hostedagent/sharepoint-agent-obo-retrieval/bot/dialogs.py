# Copyright (c) Microsoft. All rights reserved.
"""Teams SSO auth dialog: silently obtains the user's Graph token via the bot's OAuth connection,
then calls the hosted agent with that token and returns the grounded answer."""

import logging

from botbuilder.core import MessageFactory, TurnContext
from botbuilder.dialogs import (
    ComponentDialog,
    DialogTurnResult,
    WaterfallDialog,
    WaterfallStepContext,
)
from botbuilder.dialogs.prompts import OAuthPrompt, OAuthPromptSettings

from agent_client import AgentClient

logger = logging.getLogger(__name__)


class MainDialog(ComponentDialog):
    def __init__(self, connection_name: str, agent: AgentClient):
        super().__init__(MainDialog.__name__)
        self._agent = agent

        self.add_dialog(
            OAuthPrompt(
                OAuthPrompt.__name__,
                OAuthPromptSettings(
                    connection_name=connection_name,
                    title="Sign in",
                    text="Signing you in to access SharePoint…",
                    timeout=300000,
                    # SSO: with webApplicationInfo in the Teams manifest, the exchange is silent.
                    end_on_invalid_message=True,
                ),
            )
        )
        self.add_dialog(
            WaterfallDialog(
                "main",
                [self.prompt_step, self.answer_step],
            )
        )
        self.initial_dialog_id = "main"

    async def prompt_step(self, step: WaterfallStepContext) -> DialogTurnResult:
        return await step.begin_dialog(OAuthPrompt.__name__)

    async def answer_step(self, step: WaterfallStepContext) -> DialogTurnResult:
        token_response = step.result
        question = (step.options or {}).get("text", "") if isinstance(step.options, dict) else ""

        if not token_response or not token_response.token:
            await step.context.send_activity(
                MessageFactory.text("Sign-in was not completed, so I couldn't reach SharePoint.")
            )
            return await step.end_dialog()

        try:
            payload = await self._agent.ask(question, token_response.token)
            answer = AgentClient.extract_text(payload)
        except Exception as ex:  # noqa: BLE001
            logger.exception("Agent call failed")
            answer = f"Sorry — the agent call failed: {ex}"

        await step.context.send_activity(MessageFactory.text(answer))
        return await step.end_dialog()
