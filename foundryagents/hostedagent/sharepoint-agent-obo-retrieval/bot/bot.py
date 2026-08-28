# Copyright (c) Microsoft. All rights reserved.
from botbuilder.core import ConversationState, TurnContext, UserState
from botbuilder.dialogs import Dialog
from botbuilder.core.teams import TeamsActivityHandler

from helpers import run_dialog


class TeamsSsoBot(TeamsActivityHandler):
    """Runs the SSO dialog on each message and on the Teams SSO token-exchange invokes."""

    def __init__(self, conversation_state: ConversationState, user_state: UserState, dialog: Dialog):
        self._conversation_state = conversation_state
        self._user_state = user_state
        self._dialog = dialog

    async def on_turn(self, turn_context: TurnContext):
        await super().on_turn(turn_context)
        # Persist any state changes after the turn.
        await self._conversation_state.save_changes(turn_context, False)
        await self._user_state.save_changes(turn_context, False)

    async def on_message_activity(self, turn_context: TurnContext):
        await run_dialog(
            self._dialog,
            turn_context,
            self._conversation_state.create_property("DialogState"),
            options={"text": turn_context.activity.text},
        )

    async def on_teams_signin_verify_state(self, turn_context: TurnContext):
        # Continues the OAuthPrompt when Teams returns from the sign-in card.
        await run_dialog(
            self._dialog,
            turn_context,
            self._conversation_state.create_property("DialogState"),
        )

    async def on_teams_signin_token_exchange(self, turn_context: TurnContext):
        # Silent SSO token exchange (webApplicationInfo in the Teams manifest triggers this).
        await run_dialog(
            self._dialog,
            turn_context,
            self._conversation_state.create_property("DialogState"),
        )
