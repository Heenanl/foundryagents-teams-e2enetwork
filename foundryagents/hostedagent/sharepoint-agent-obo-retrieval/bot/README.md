# Teams SSO bot — supplies the per‑user token to the hosted SharePoint agent

This bot is the **only new component** needed to run the hosted Option C agent
([`../`](../README.md)) in **Microsoft Teams** with **per‑user permission trimming**. It does Teams
**SSO** to get the user's token, and forwards it to the agent's `/responses` via `structured_inputs`.
It **replaces** the Foundry auto‑published Teams bot (which can't supply a user token).

Architecture: [`../../../../guides/hosted-sharepoint-teams-sso-architecture.md`](../../../../guides/hosted-sharepoint-teams-sso-architecture.md)

## What it does (per message)
1. Teams **SSO** → the user's token (silent, via the bot's OAuth connection configured with Graph scopes).
2. Calls the hosted agent `/responses` with `structured_inputs.userToken = "Bearer <token>"`
   (the bot authenticates to Foundry with its **own** identity; the user identity rides in the body).
3. Returns the agent's grounded answer + citations to Teams.

## Files
```
bot/
├── app.py             ← aiohttp host + Bot Framework CloudAdapter
├── bot.py             ← TeamsActivityHandler (runs the SSO dialog + token-exchange invokes)
├── dialogs.py         ← OAuthPrompt (SSO) → calls the agent
├── agent_client.py    ← POST /responses with structured_inputs.userToken
├── helpers.py         ← dialog runner
├── config.py          ← env config
├── requirements.txt
├── manifest/manifest.json   ← Teams app manifest (webApplicationInfo = SSO)
└── setup/Register-SsoApp.ps1 ← creates/configures the Entra app (scopes, access_as_user, pre-auth Teams, secret)
```

## Setup (once)

### 1. Entra app registration
```powershell
cd setup
./Register-SsoApp.ps1 -DisplayName "SharePoint KB Teams SSO Bot"
```
Save the printed `MicrosoftAppId`, `MicrosoftAppPassword`, `MicrosoftAppTenantId`, and Application ID URI.
Then a **Global Admin grants admin consent** (link printed by the script).

### 2. Azure Bot registration + OAuth connection
- Create an **Azure Bot** (SingleTenant) with `msaAppId` = the app id from step 1, messaging endpoint
  `https://<your-bot-host>/api/messages`. (You can reuse the pattern in
  [`infra/bot-service.bicep`](../../../../infra/bot-service.bicep).)
- Add an **OAuth Connection** on the bot (name it e.g. `graph`) using the **Azure Active Directory v2**
  provider with this app's client id/secret/tenant and **scopes**:
  `Files.Read.All Sites.Read.All openid profile offline_access`.
  > This is what makes the token the bot receives a **Graph** token directly — no separate OBO call.

### 3. Deploy the bot
Host `app.py` anywhere the Bot Channel can reach (App Service / Container Apps / Functions custom handler).
Set env:
```
MicrosoftAppId=<from step 1>
MicrosoftAppPassword=<from step 1>
MicrosoftAppTenantId=<from step 1>
MicrosoftAppType=SingleTenant
OAUTH_CONNECTION_NAME=graph
AGENT_RESPONSES_ENDPOINT=https://<account>.services.ai.azure.com/api/projects/<project>/agents/agent-framework-agent-sharepoint-obo/endpoint/protocols/openai/responses?api-version=v1
STRUCTURED_INPUT_TOKEN_KEY=userToken
```
> The bot must reach the agent's `/responses` (through the APIM bridge for a private Foundry).
> The identity `app.py` runs as needs **Foundry User** on the project (to call `/responses`).

### 4. Teams app package
Fill `{{BOT_APP_ID}}` in `manifest/manifest.json`, add `color.png` (192×192) and `outline.png`
(32×32), zip the three files, and **sideload** into Teams (or publish to your org catalog).

## Test end‑to‑end
1. Open the app in Teams and send a question answerable by a doc on the configured site.
2. First time: approve the SSO consent prompt. After that it's silent.
3. Expect a grounded answer with **citations** to that site — **trimmed to your permissions**.

Permission‑trimming check: ask the same question as a user who **can** read a doc vs one who **can't**;
the second must not get that doc's content/citation.

### Diagnostics you may see (from the agent, relayed by the bot)
- `NO_USER_TOKEN` — the token wasn't forwarded (check the OAuth connection / SSO).
- `RETRIEVAL_ERROR 403 … User does not have valid license` — the user isn't **Copilot‑licensed** and
  the tenant lacks **Retrieval API pay‑as‑you‑go**. **Licensing gate — not a code issue.**
- `NO_RESULTS` — the user has no access to matching content on the site.

## Reuse for other agents
The bot + Entra app are **agent‑agnostic**. To front another hosted agent, deploy another instance (or
add routing) pointing `AGENT_RESPONSES_ENDPOINT` at that agent — **no new auth code**.

## Notes
- Bot Framework SDK auth boilerplate can vary slightly by version; pin `botbuilder-*` to a matching set.
- Everything downstream still requires **Retrieval API license/paygo** (see the agent README).
