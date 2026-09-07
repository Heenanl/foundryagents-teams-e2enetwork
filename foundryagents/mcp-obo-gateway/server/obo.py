# Copyright (c) Microsoft. All rights reserved.
"""Generic On-Behalf-Of exchange. Turns the user token that Foundry forwards into a downstream
token for ANY resource/scopes a provider asks for. This is the reusable core — providers only
declare their target scopes; they never touch auth.

Two client-credential modes for the gateway's own Entra app:
  - secret: GATEWAY_CLIENT_SECRET set (simplest; fine for dev).
  - federated (no secret): a managed identity supplies the client assertion via workload-identity
    federation. Leave GATEWAY_CLIENT_SECRET empty and add a federated credential on the app that
    trusts the managed identity. This is the hardened, secret-less path."""

import asyncio

import msal


class Obo:
    """Confidential-client OBO. One instance is shared by all providers.

    Pass client_secret for the secret path, OR leave it empty and pass managed_identity_client_id
    (or rely on the default MI) for the secret-less federated path."""

    _EXCHANGE_SCOPE = "api://AzureADTokenExchange/.default"

    def __init__(
        self,
        tenant_id: str,
        client_id: str,
        client_secret: str = "",
        managed_identity_client_id: str = "",
    ):
        if client_secret:
            credential: object = client_secret
        else:
            # Federated: the MI's token for the token-exchange audience IS the client assertion.
            # Fetched fresh on each request so rotation is automatic; no secret is stored anywhere.
            from azure.identity import ManagedIdentityCredential

            mi = (
                ManagedIdentityCredential(client_id=managed_identity_client_id)
                if managed_identity_client_id
                else ManagedIdentityCredential()
            )
            credential = {"client_assertion": lambda: mi.get_token(self._EXCHANGE_SCOPE).token}
        self._app = msal.ConfidentialClientApplication(
            client_id=client_id,
            client_credential=credential,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )

    async def exchange(self, user_token: str, scopes: list[str]) -> str:
        """Exchange the inbound user token for a downstream token with the given scopes.

        MSAL caches the result keyed by the assertion hash, so repeat calls in a session do not
        re-hit Entra (Entra's own guidance for avoiding 429s on a middle tier)."""
        result = await asyncio.to_thread(
            self._app.acquire_token_on_behalf_of,
            user_assertion=user_token,
            scopes=scopes,
        )
        if "access_token" not in result:
            # Surface AADSTS codes + any claims challenge so an operator can tell a Conditional
            # Access / consent problem (fixable) from a bug. e.g. AADSTS65001 = consent missing.
            codes = ", ".join(f"AADSTS{c}" for c in result.get("error_codes", [])) or "no AADSTS code"
            claims = result.get("claims")
            raise RuntimeError(
                f"OBO failed: {result.get('error')} ({codes}) - "
                f"{result.get('error_description', '')[:300]}"
                + (f" | claims challenge present" if claims else "")
            )
        return result["access_token"]
