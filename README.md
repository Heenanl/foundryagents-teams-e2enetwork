# Private Foundry → Microsoft Teams Bridge

Make **private (VNet-isolated) Azure AI Foundry hosted agents** work in **Microsoft Teams**
and **Microsoft 365 Copilot**.

An **API Management Standard v2** instance bridges the public Azure Bot Service to the
private Foundry endpoint, so Foundry never needs public network access.

> **Foundry removed the one-click "Publish to Teams" button for private-networking
> projects.** This repo replaces it with the supported REST-API publish flow
> ([scripts/Publish-AgentToTeams.ps1](scripts/Publish-AgentToTeams.ps1)) — it creates the
> Azure Bot, points it at the APIM bridge, and calls Foundry's Microsoft 365 publish API.
> See [publish-copilot-virtual-network](https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network).

```
Teams ──► Azure Bot Service ──► APIM (public gateway) ──► Private Foundry (via VNet)
```

---

## 🏗️ Architecture

```
                          INBOUND: Teams ↔ private Foundry (the APIM bridge)
┌──────────┐   HTTPS    ┌──────────────────┐  webhook   ┌─────────────────────┐
│  Teams   │ ─────────► │ Azure Bot Service │ ─────────► │  APIM Standard v2   │
│  client  │ ◄───────── │ (public, M365)    │ ◄───────── │  (public gateway)   │
└──────────┘            └──────────────────┘            └─────────┬───────────┘
                                                                  │ VNet outbound
                                                                  │ integration
                                                        ┌─────────▼───────────┐
                                                        │  Private Foundry     │
                                                        │  hosted agent        │
                                                        └─────────┬───────────┘
        OUTBOUND (optional): per-user tool call        per-user   │ tool call
        for the SharePoint Retrieval API route         (OAuth2 passthrough)
                                                        ┌─────────▼───────────┐
                                                        │  MCP-OBO gateway     │──► Entra (OBO)
                                                        │  (this repo)         │──► Copilot Retrieval API
                                                        └─────────────────────┘
```

- **INBOUND (the bridge).** **One templated APIM operation**
  (`/api/projects/{project}/agents/{agent}/...`) serves **every** agent — configured once.
  Foundry stays private; only APIM's gateway is public. The bridge is **auth-transparent** and
  **version-agnostic** (preserves each bot's `api-version`, injecting a fallback only if missing).
- **OUTBOUND (optional).** A hosted agent can call out to the **[MCP-OBO gateway](foundryagents/mcp-obo-gateway/README.md)**
  via an OAuth2 identity-passthrough connection to reach **SharePoint per-user** through the Copilot
  Retrieval API. This is a **separate leg** from the bridge and only used by the
  `sharepoint-agent-copilot-retrieval` sample; the Work IQ / Databricks samples use Microsoft-hosted
  MCP endpoints instead.

---

## 🚀 Features

- **Private-by-design** — Foundry data plane is never exposed publicly.
- **REST-API publish** — replaces the removed Foundry portal button: creates the bot,
  points it at the bridge, and publishes to Microsoft 365 / Teams in one command.
- **Scales to many agents** — single templated operation; new agents need only publishing.
- **Idempotent onboarding reconciler** — repoints new bots; safe to re-run or schedule.
- **Infrastructure as Code** — Bicep modules + `.bicepparam`.
- **Auth-transparent** — Bot Framework JWT forwarded unchanged; Foundry validates it.

---

## 📋 Prerequisites

- An existing **private Azure AI Foundry** deployment with end-to-end networking
  (VNet + private endpoints + private DNS), provisioned from the official
  **private network standard agent setup** template:
  [foundry-samples/infrastructure-setup-bicep/15-private-network-standard-agent-setup](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup).
  This bridge assumes that deployment already exists; it does **not** create the Foundry
  account, project, VNet, or private endpoints.
- Azure CLI (`az login`) with **Contributor** on the resource group.
- **PowerShell 7+**.
- A **free /27+ subnet block** in the Foundry VNet for APIM integration.

> **Note — no Foundry project name parameter.** The bridge is project- and agent-agnostic.
> The APIM operation uses `{project}` and `{agent}` as path wildcards
> (`/api/projects/{project}/agents/{agent}/...`), so a single deployment serves **every**
> project and agent in the Foundry account. You only configure `foundryHost` (the account
> host); the project and agent are supplied per-request from each bot's endpoint path.


---

## 📁 Project Structure

```
.
├── deploy.ps1                          # Orchestrator: deploy infra + onboard bots
├── README.md                           # This file
│
├── infra/                              # Infrastructure as Code (the APIM bridge)
│   ├── main.bicep                      # Orchestration template
│   ├── main.parameters.bicepparam      # Parameters (edit before deploy)
│   ├── resourcegroup.config.json       # Resource group + tags
│   ├── bot-service.bicep               # Per-agent Azure Bot + Teams channel (REST publish)
│   └── modules/                        # network / apim / apim-config / apim-api / apim-policies
│
├── apim-policies/
│   └── foundry-activity-policy.xml     # Bridge policy (api-version + hardening notes)
│
├── scripts/
│   ├── Publish-AgentToTeams.ps1        # Create bot + publish agent (REST) via the bridge
│   ├── Onboard-Agents.ps1              # Reconciler: repoint existing bots to APIM
│   └── Register-GatewayApp.ps1         # Register the Entra app for the MCP-OBO gateway
│
├── foundryagents/                      # Agent samples (optional — deploy onto the bridge above)
│   ├── hostedagent/                    #   sharepoint-agent-workiq · databricks-agent ·
│   │                                   #   sharepoint-agent-copilot-retrieval
│   ├── promptagent/                    #   sharepoint-agent-grounding-tool
│   └── mcp-obo-gateway/                #   per-user OBO gateway for the Copilot Retrieval API
│
├── guides/
│   └── agent-tool-support-matrix.md    # Which agent/tool for SharePoint access — start here
│
└── tests/
    └── test_bridge.py                  # Routing/connectivity test (+ README, requirements)
```

---

## 🤖 Foundry agents (optional)

The bridge is agent-agnostic — it carries **any** agent's Teams traffic. This repo also ships
ready-to-deploy **agent samples** under [foundryagents/](foundryagents/). To add an agent, start with
the one-page decision matrix [guides/agent-tool-support-matrix.md](guides/agent-tool-support-matrix.md),
then open the matching sample's README and run `azd up`:

- **Hosted + Teams + per-user + one SharePoint site** → [mcp-obo-gateway](foundryagents/mcp-obo-gateway/README.md) + [sharepoint-agent-copilot-retrieval](foundryagents/hostedagent/sharepoint-agent-copilot-retrieval/README.md)
- **Hosted + Teams, broad M365 (no site scoping)** → [sharepoint-agent-workiq](foundryagents/hostedagent/sharepoint-agent-workiq/README.md)
- **Prompt agent, site-scoped (not hosted)** → [sharepoint-agent-grounding-tool](foundryagents/promptagent/sharepoint-agent-grounding-tool/README.md)

---

## 🛠️ Deployment

### 1. Configure

Edit [infra/main.parameters.bicepparam](infra/main.parameters.bicepparam):

```bicep
param location = 'swedencentral'
param vnetName = 'agent-vnet-test'           // your private Foundry VNet
param apimSubnetPrefix = '192.168.3.0/27'    // a FREE /27 block in that VNet
param apimName = 'apim-foundry-bridge'
param apimPublisherEmail = 'you@example.com'  // CHANGE THIS
param foundryHost = 'https://<account>.services.ai.azure.com'
param foundryApiVersion = '2025-11-15-preview'
```

And [infra/resourcegroup.config.json](infra/resourcegroup.config.json) (`resourceGroupName`, `location`).

### 2. Deploy

```powershell
az login

# Preview (Bicep what-if + dry-run onboarding)
./deploy.ps1 -WhatIf

# Full deploy + onboard existing bots
./deploy.ps1
```

APIM provisioning takes ~10 minutes on first deploy.

### 3. Publish an agent to Teams

The Foundry portal's one-click publish button is unavailable for private-networking
projects. Create the agent's bot and publish it via the REST flow:

```powershell
./scripts/Publish-AgentToTeams.ps1 `
    -ResourceGroup rg-foundry-privateagent `
    -AgentName <agent-name> `
    -ProjectEndpoint https://<account>.services.ai.azure.com/api/projects/<project> `
    -ApimName apim-foundry-bridge
```

This creates the Azure Bot (endpoint pointed at the APIM bridge), enables the Teams
channel, and calls Foundry's Microsoft 365 publish API. Use `-PublishScope Tenant` for
org-wide publishing (needs Microsoft 365 admin approval); increment `-AppVersion` to change
user-facing metadata on republish. Add `-WhatIf` to preview.

> **Reconcile existing bots.** If a bot was created outside this repo (e.g. still pointing
> at the private Foundry host), repoint it to the bridge with `./deploy.ps1 -OnboardOnly`.

---

## 🧪 Testing

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r tests/requirements.txt

Copy-Item tests/.env.template tests/.env   # fill in gateway/project/agent
python tests/test_bridge.py
```

A correctly routed unsigned probe returns **401** (Foundry's auth challenge) — that's a PASS.
See [tests/README.md](tests/README.md).

---

## 🔒 Security

| Hop | Credential | Validated by |
|---|---|---|
| Teams → Bot Service | Channel registration (internal) | Bot Service |
| Bot Service → APIM | Bot Framework JWT (aud = bot App ID) | *(passed through)* |
| APIM → Foundry | Same JWT, forwarded unchanged | **Foundry** |
| Foundry → Bot Service (reply) | Bot App ID + secret (Foundry-managed) | Entra / Bot Service |

**Recommended hardening** (see commented block in the policy):
- Enable `validate-jwt` in APIM to reject non-Bot-Framework tokens at the edge.
- Add an inbound IP filter for the `AzureBotService` service tag.

---

## 🐛 Troubleshooting

| Symptom | Likely cause |
|---|---|
| `403` in Bot Service Web Chat | Bot endpoint still points at the private host — run `./deploy.ps1 -OnboardOnly` |
| `500` | APIM cannot resolve/reach Foundry (DNS/VNet) or wrong `foundryHost` |
| `400` | Wrong path suffix or missing `api-version` |
| `202`, no reply | Normal — reply is async via Bot Service `serviceUrl` |

> Foundry-published bots are **not** listed by `az bot list`. Use
> `az resource list --resource-type Microsoft.BotService/botServices`.

---

## 📚 Additional Resources

- [Azure API Management v2 tiers](https://learn.microsoft.com/azure/api-management/v2-service-tiers-overview)
- [APIM VNet outbound integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [Azure AI Foundry](https://learn.microsoft.com/azure/ai-foundry/)
