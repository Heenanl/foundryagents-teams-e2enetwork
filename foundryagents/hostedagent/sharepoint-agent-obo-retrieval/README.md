# SharePoint per-user grounding from a HOSTED agent (Retrieval API + `structured_inputs`)

The route that gives **all three** at once — **per‑user permission trimming**, **single‑site scoping**,
and **hosted container + Teams** — which no single built‑in tool does.

| | Built‑in SharePoint tool | Work IQ | **This sample** |
| --- | --- | --- | --- |
| Per‑user trimming | ✅ | ✅ | ✅ |
| Scope to one site | ✅ | ❌ (broad M365) | ✅✅ (`filterExpression`) |
| Hosted container / Teams | ❌ | ✅ | ✅ |

## How it works

```
Teams client
  │  Teams SSO / OBO → user's Graph token (Files.Read.All + Sites.Read.All)
  ▼
Bot Service ──(put "Bearer <token>" in structured_inputs.userToken)──► APIM bridge ─► Foundry HOSTED agent
                                                                                         │
      main.py reads request["structured_inputs"]["userToken"]  ◄────────────────────────┘
      → POST /copilot/retrieval  { dataSource: sharePoint, filterExpression: path:"<SITE>/" }
      → permission-trimmed, single-site extracts → model answers WITH citations
```

**Why this works (and the built‑in tool doesn't):** a hosted container authenticates to Foundry with
its **managed identity** (app‑only), which the SharePoint grounding tool rejects. Here the container
uses its managed identity only for the **model** call; the **retrieval** uses the **user's token**
passed in via `structured_inputs`. We verified end‑to‑end that a hosted container receives
`structured_inputs` (the token value arrives intact) — see the repo notes / the comparison guide.

> The built‑in `sharepoint_grounding_preview` tool can't be fed a token, so this sample calls the
> **Retrieval API directly** — which is also where the precise `filterExpression` site scoping comes from.

## Token model

Pass a **Graph** access token (audience `https://graph.microsoft.com`, delegated scopes
**`Files.Read.All` + `Sites.Read.All`**) as `structured_inputs.userToken`. Your **bot** obtains it via
**Teams SSO + On‑Behalf‑Of**. The container stays **secret‑free** (no confidential‑client app needed).

_Alternative:_ pass a token scoped to your own API and have the container do the OBO exchange itself
(needs a confidential client + secret). Left out here on purpose to keep the container clean.

## Prerequisites

1. **Licensing:** each calling user has a **Microsoft 365 Copilot license**, or the tenant has the
   **Microsoft 365 Copilot Retrieval API** pay‑as‑you‑go service enabled (this is a *separate* meter
   from "SharePoint agents"; its prerequisite is ≥1 Copilot license in the tenant).
2. Same Entra tenant for the SharePoint site and the Foundry project.
3. The hosted agent's identity has **Foundry User** on the project; calling users have **Foundry User**
   + **Foundry Agent Consumer**.
4. Each user has at least **READ** on the SharePoint site being grounded.

## Layout

```
sharepoint-agent-obo-retrieval/
├── README.md
├── agent-framework-agent-with-foundry-toolbox-responses/
│   ├── azure.yaml
│   └── src/agent-framework-agent-sharepoint-obo/
│       ├── main.py            ← reads structured_inputs.userToken → Retrieval API (site-scoped) → grounded answer
│       ├── requirements.txt
│       ├── Dockerfile
│       └── .env.example
└── client/
    └── invoke_with_user_token.py   ← local stand-in for the Teams bot (Teams SSO + OBO in prod)
```

## Configure

Set in the deploy env:

```
AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-4.1
FOUNDRY_PROJECT_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>
SHAREPOINT_SITE_URL=https://<company>.sharepoint.com/sites/<site>   # the one site to scope to
RETRIEVAL_API_URL=https://graph.microsoft.com/v1.0/copilot/retrieval
STRUCTURED_INPUT_TOKEN_KEY=userToken
MAX_RESULTS=10
USE_EXISTING_AI_PROJECT=true
```

## Deploy

Same pattern as the other hosted samples in this repo (the `azd ai agent init` scaffolder is buggy on
current builds): create a self‑contained `.azd-deploy/` copy with a pre‑seeded `.azure/<env>/.env`, then
`azd deploy -e <env> --no-prompt` (provision is a no‑op via `USE_EXISTING_AI_PROJECT=true`).

## Test

Locally (stand‑in for the bot):

```powershell
cd client
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install httpx azure-identity python-dotenv
# set AGENT_RESPONSES_ENDPOINT, ENTRA_CLIENT_ID, ENTRA_TENANT_ID, QUERY
python invoke_with_user_token.py
```

Expected (licensed user): a grounded answer with **URL citations** to docs on the configured site.
Diagnostics you may see from `main.py` instead of an answer:
- `NO_USER_TOKEN` — the caller didn't pass `structured_inputs.userToken`.
- `RETRIEVAL_ERROR 403 … User does not have valid license` — user isn't Copilot‑licensed / not covered
  by Retrieval API pay‑as‑you‑go.
- `NO_RESULTS` — user has no access to matching content on the site.

### Permission‑trimming check
Ask the same question as a user who **can** read a doc vs one who **can't** — the second must not get
that doc's content/citation. Different results per user = OBO trimming is working.

## Teams wiring (production)

The APIM bridge in this repo forwards the responses call; add two things at the **bot**:
1. A **Teams SSO** OAuth connection to get the user's AAD token, then **OBO** → `Files.Read.All` +
   `Sites.Read.All`.
2. Inject that token into the request body as `structured_inputs.userToken` before it hits APIM.

## Related
- [`../sharepoint-agent-retrievalapi`](../sharepoint-agent-retrievalapi/README.md) — the built‑in tool
  (prompt/in‑process only).
- [`../sharepoint-agent-workiq`](../sharepoint-agent-workiq/README.md) — Work IQ (hosted/Teams, no site scoping).
- [`../../../guides/sharepoint-access-via-foundry-agents.md`](../../../guides/sharepoint-access-via-foundry-agents.md) — full options comparison.
