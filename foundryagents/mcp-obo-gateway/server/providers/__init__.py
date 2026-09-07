# Copyright (c) Microsoft. All rights reserved.
import importlib


def load(names: list[str]) -> list:
    """Import enabled provider modules by name (providers/<name>.py)."""
    return [importlib.import_module(f"providers.{n.strip()}") for n in names if n.strip()]
