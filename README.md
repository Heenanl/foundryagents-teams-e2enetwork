# Private Foundry → Microsoft Teams Bridge

Make **private (VNet-isolated) Azure AI Foundry hosted agents** work in **Microsoft Teams**
while keeping Foundry's **one-click Teams publish** experience.

An **API Management Standard v2** instance bridges the public Azure Bot Service to the
private Foundry endpoint, so Foundry never needs public network access.

```
Teams ──► Azure Bot Service ──► APIM (public gateway) ──► Private Foundry (via VNet)
```

---

## 🏗️ Architecture

```
┌──────────┐   HTTPS    ┌──────────────────┐  webhook   ┌─────────────────────┐
│  Teams   │ ─────────► │ Azure Bot Service │ ─────────► │  APIM Standard v2   │
│  client  │ ◄───────── │ (public, M365)    │ ◄───────── │  (public gateway)   │
└──────────┘            └──────────────────┘            └─────────┬───────────┘
                                                                  │ VNet outbound
                                                                  │ integration
                                                        ┌─────────▼───────────┐
                                                        │  Private Foundry     │
                                                        │  *.services.ai...    │
                                                        │  (private endpoint)  │
                                                        └─────────────────────┘
```

- **One templated APIM operation** (`/api/projects/{project}/agents/{agent}/...`) serves
  **every** agent — current and future. APIM is configured once.
- **Foundry stays private.** Only APIM's gateway is public; APIM reaches Foundry over the VNet.
- **Version-agnostic.** The bridge preserves whatever `api-version` Foundry sets per bot;
  the policy injects a fallback only if missing.

---

## 🚀 Features

- **Private-by-design** — Foundry data plane is never exposed publicly.
- **Preserves Foundry one-click publish** — only the bot's messaging endpoint is repointed.
- **Scales to many agents** — single templated operation; new agents need only onboarding.
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
├── infra/                              # Infrastructure as Code
│   ├── main.bicep                      # Orchestration template
│   ├── main.parameters.bicepparam      # Parameters (edit before deploy)
│   ├── resourcegroup.config.json       # Resource group + tags
│   └── modules/
│       ├── network.bicep               # APIM subnet + NSG
│       ├── apim.bicep                  # APIM Standard v2 + VNet integration
│       ├── apim-config.bicep           # Named values (foundry-api-version)
│       ├── apim-api.bicep              # Bridge API + templated all-agents operation
│       └── apim-policies.bicep         # Policy attachment
│
├── apim-policies/
│   └── foundry-activity-policy.xml     # Bridge policy (api-version + hardening notes)
│
├── scripts/
│   └── Onboard-Agents.ps1              # Reconciler: repoint Foundry bots to APIM
│
├── tests/
│   ├── README.md
│   ├── requirements.txt
│   ├── .env.template
│   └── test_bridge.py                  # Routing/connectivity test
│
├── foundryagents/
│   └── hostedagent/                    # Sample hosted agent (azd) bound to the
│                                       # existing private Foundry project
│
└── teams-relay/                        # (reference) self-hosted relay-bot alternative
```

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

### 3. Onboard new agents

After publishing a **new** agent from the Foundry portal, repoint its bot:

```powershell
./deploy.ps1 -OnboardOnly
```

---

## � Hosted agents

The same bridge works for **hosted agents** (containerized agents that run inside
Foundry), not just prompt agents. A sample lives in
[foundryagents/hostedagent](foundryagents/hostedagent), scaffolded with `azd ai agent`
and bound to the **existing** private Foundry project (no new Foundry is provisioned).

Deploy the agent into the existing project:

```powershell
cd foundryagents/hostedagent
# Bind to your existing project and a deployed model:
azd ai agent init -m "<manifest-url>" --project-id "<project-resource-id>" --model-deployment "gpt-4.1"
azd deploy <service-name>
```

Then publish it to Teams from the Foundry portal and onboard its bot to the bridge:

```powershell
./deploy.ps1 -OnboardOnly
```

Updates flow automatically: the Teams bot endpoint targets the agent by **name**
(version-less), so each `azd deploy` that creates a new active version is served
immediately — no re-onboarding needed.

> **Hosted-agent gotchas** (learned the hard way):
> - The image is pulled by the **project** managed identity over the ACR **public**
>   endpoint — grant it `AcrPull`. Private ACR isn't supported for hosted agents.
> - Use a standard (non-ABAC) ACR; ABAC mode breaks the remote build.
> - Give the container enough resources (e.g. `1` CPU / `2Gi`); the agent-framework
>   image is too large for the smallest tier.
> - Deploying to a private Foundry from outside the VNet needs a temporary
>   `publicNetworkAccess` toggle for the management calls; restore it to `Disabled` after.

---

## �🧪 Testing

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
