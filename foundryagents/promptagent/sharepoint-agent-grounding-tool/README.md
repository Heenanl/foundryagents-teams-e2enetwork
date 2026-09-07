# SharePoint grounding tool — prompt / in-process agent (per-user OBO)

> A **prompt-style** agent that runs **in-process under the signed-in user** — **not** a deployed
> hosted container. The SharePoint grounding tool only works under the user's identity (see the
> table below), so it lives with the prompt agents, not the hosted ones.

Grounds answers on a SharePoint site using the Foundry **SharePoint tool**
(`sharepoint_grounding_preview`), which is backed by the **Microsoft 365 Copilot Retrieval API**.
It runs **on behalf of the signed-in user**, so answers are trimmed to that user's SharePoint
permissions.

## ⚠️ Read this first — where this works (and where it doesn't)

The SharePoint grounding tool requires the **signed-in user's delegated identity (OBO)**:

| Runs under | Works? |
| --- | --- |
| Signed-in **user** identity (`az login` as the user; playground prompt agent) | ✅ Yes |
| A **deployed hosted-agent** container (its **managed identity** = app-only) | ❌ No — app-only is rejected |
| Agent **published to Microsoft Teams** | ❌ No — explicitly unsupported |

So this sample runs the agent **in-process under the user's identity** (the doc's "Hosted Agents"
pivot), which is the path that actually works. It is **not** deployable as a Foundry hosted
container for SharePoint grounding, and it will **not** work in Teams — that's a documented tool
limitation, not a bug. (This is the same reason the Work IQ route exists for the Teams scenario.)

Ref: [Use SharePoint tool with the agent API](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/sharepoint)
(see "Before you start" and "Limitations").

## Why the Retrieval API here

- Grounds on **SharePoint / OneDrive / Copilot connectors**, permission-trimmed, no separate index.
- **Licensing that fits a tenant without M365 Copilot licenses:** the Retrieval API is free for
  Copilot-licensed users, or available via **pay-as-you-go** for **tenant-level** sources
  (SharePoint + Copilot connectors) for non-licensed users. OneDrive (user-level) needs a Copilot
  license. So **SharePoint works via pay-as-you-go**.
  Ref: [Retrieval API overview](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/ai-services/retrieval/overview),
  [pay-as-you-go](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/ai-services/retrieval/paygo-retrieval).

## Prerequisites

1. **License / billing:** the calling user has a **Microsoft 365 Copilot** license, **or** the tenant
   has **Retrieval API pay-as-you-go** enabled (M365 admin center → Copilot → Cost management /
   Pay-as-you-go). SharePoint is tenant-level, so pay-as-you-go covers it.
2. **Same Entra tenant** for the SharePoint site and the Foundry project (no cross-tenant).
3. **RBAC:** the user has at least **Foundry User** on the Foundry project.
4. **SharePoint:** the user has at least **READ** on the SharePoint site/folder being grounded.
5. A **SharePoint connection** in the Foundry project (below).
6. `az login` as the **user** (delegated identity), and Python 3.10+.

## Step 1 — Create the SharePoint connection

In Foundry → your project → **Management / Settings → Connections → New connection → SharePoint**,
enter the **site or folder URL** (not the raw browser address):

- Site: `https://<company>.sharepoint.com/sites/<site_name>`
- Folder: `https://<company>.sharepoint.com/sites/<site_name>/Shared%20Documents/<folder>`

Save it and note the **connection name** → put it in `.env` as `SHAREPOINT_CONNECTION_NAME`.
(Only **one** SharePoint tool per agent is supported.)

## Step 2 — Run it as the user

```powershell
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env   # then edit .env

az login    # sign in AS THE TEST USER (delegated identity that has READ on the site)
python sharepoint_agent.py
```

You should get an answer grounded in the site content, with **URL citations** to the source docs.

## Step 3 — Verify permission-trimming (the actual test)

1. Pick a document one user can read and another can't.
2. `az login` as the **user with access** → ask a question answered by that doc → expect the answer
   **and a citation**.
3. `az login` as the **user without access** → ask the same question → expect **no** content/citation
   from the restricted doc.

Different results per user = SharePoint OBO permission-trimming is working (via the Retrieval API).

## Files

```
sharepoint-agent-grounding-tool/
├── README.md
├── sharepoint_agent.py     ← in-process agent, runs under the signed-in user's identity
├── requirements.txt
└── .env.example
```

## Contrast with the other SharePoint agent in this repo

- [`../../hostedagent/sharepoint-agent-workiq`](../../hostedagent/sharepoint-agent-workiq/README.md) — **Work IQ** (A2A) route:
  works from a **hosted agent published to Teams**, needs **Copilot Credits** billing.
- **This one** — **SharePoint grounding tool / Retrieval API**: works **per-user** (playground /
  in-process user identity), supports **pay-as-you-go** (no Copilot license needed for SharePoint),
  but is **not** supported from a deployed hosted container or in Teams.
