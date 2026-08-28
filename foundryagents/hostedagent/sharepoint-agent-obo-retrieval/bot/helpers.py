# Copyright (c) Microsoft. All rights reserved.
from botbuilder.core import StatePropertyAccessor, TurnContext
from botbuilder.dialogs import Dialog, DialogSet, DialogTurnStatus


async def run_dialog(
    dialog: Dialog,
    turn_context: TurnContext,
    accessor: StatePropertyAccessor,
    options: dict | None = None,
) -> None:
    dialog_set = DialogSet(accessor)
    dialog_set.add(dialog)

    dialog_context = await dialog_set.create_context(turn_context)
    result = await dialog_context.continue_dialog()
    if result.status == DialogTurnStatus.Empty:
        await dialog_context.begin_dialog(dialog.id, options)
