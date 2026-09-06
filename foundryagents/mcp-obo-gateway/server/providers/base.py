# Copyright (c) Microsoft. All rights reserved.
"""Provider contract. A provider adds one or more MCP tools that call a downstream API on behalf
of the user. It declares the OBO target scopes; the gateway does the token exchange and passes the
downstream token in. Add a new tool = add a new provider module; no auth/MCP plumbing to touch."""

from __future__ import annotations

from typing import Awaitable, Callable, Protocol

# Given (downstream_token, **tool_args) -> result. The gateway injects a ready-to-use token.
ExchangeFn = Callable[[list[str]], Awaitable[str]]


class Provider(Protocol):
    name: str

    def register(self, mcp, exchange: ExchangeFn) -> None:
        """Register this provider's MCP tool(s) on the FastMCP instance.

        `exchange(scopes)` returns a downstream access token obtained via OBO from the current
        request's user token — call it inside each tool with the scopes that tool needs.
        """
        ...
