# Copyright (c) Microsoft. All rights reserved.
import os

from dotenv import load_dotenv

load_dotenv()


class Config:
    PORT = int(os.getenv("PORT", "8000"))

    # The gateway's OWN Entra app (confidential client) — used for the OBO exchange.
    TENANT_ID = os.environ.get("GATEWAY_TENANT_ID", "")
    CLIENT_ID = os.environ.get("GATEWAY_CLIENT_ID", "")
    # Secret path (dev). Leave empty to use the secret-less federated path below.
    CLIENT_SECRET = os.environ.get("GATEWAY_CLIENT_SECRET", "")
    # Federated (hardened) path: managed identity that the gateway app federates to. Empty = default MI.
    MANAGED_IDENTITY_CLIENT_ID = os.environ.get("GATEWAY_MI_CLIENT_ID", "")

    # Verify the inbound bearer token (audience/issuer/scope) BEFORE running any tool. Rejects a
    # token minted for another resource. Turn off only for local testing without a real token.
    VERIFY_TOKENS = os.getenv("VERIFY_TOKENS", "true").lower() != "false"
    # Scope the gateway app exposes and Foundry requests (the `scp` claim we require).
    REQUIRED_SCOPES = [
        s.strip() for s in os.getenv("REQUIRED_SCOPES", "access_as_user").split(",") if s.strip()
    ]
    # Public URL of this gateway (for RFC 9728 protected-resource metadata). e.g. https://host/
    SERVER_URL = os.getenv("SERVER_URL", "").rstrip("/")

    # Comma-separated provider module names to enable (providers/<name>.py).
    ENABLED_PROVIDERS = [
        p for p in os.getenv("ENABLED_PROVIDERS", "whoami,copilot_retrieval").split(",") if p.strip()
    ]
