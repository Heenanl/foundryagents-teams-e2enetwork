# Foundry agent audit & attribution ("who created which agent")

Microsoft Foundry **agents are created through the project data plane**, not Azure Resource
Manager. Two consequences:

- Agent create/update/delete **does not appear in the Azure Activity Log** (that only tracks
  control‑plane / ARM operations).
- The **agent object itself has no author** — it stores a `created_at` timestamp and `version`,
  but **no `createdBy` / UPN**. (Connections *do* record a creator; agents do not.)

So out of the box you **cannot** tell who created an existing agent, and there is no
per‑version change history attributable to a person.

## The fix: data‑plane audit logging → Log Analytics

Enable an Azure Monitor **diagnostic setting** on the Foundry (Cognitive Services) account that
streams the data‑plane log categories to a Log Analytics workspace. After that, every agent
operation is logged **with the caller's Entra object ID**, which resolves to a user.

> ⚠️ This is **forward‑looking only** — it captures operations that happen **after** you enable
> it. It cannot retroactively attribute agents that already exist.

### 1. Enable it

```powershell
./Enable-FoundryAgentAuditLogging.ps1 `
  -AccountResourceId   "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>" `
  -WorkspaceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<law>"
```

Enables the **`Audit`** and **`RequestResponse`** categories (add `-IncludeTrace` for verbose
tracing). Requires `az login` with Monitoring Contributor (or Contributor) on the account.

### 2. Query it

Run [agent-attribution.kql](agent-attribution.kql) in the Log Analytics workspace. Core query:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where OperationName startswith "Projects_Wildcard_Post"      // create/update
     or OperationName startswith "Projects_Wildcard_Delete"    // delete
| extend p = parse_json(properties_s)
| project TimeGenerated, OperationName, Result = ResultSignature,
          CallerObjectId = tostring(p.objectId)
| order by TimeGenerated desc
```

### 3. Resolve an object ID to a person

```powershell
az ad user show --id <CallerObjectId> --query "{name:displayName, upn:userPrincipalName}" -o json
```

## Verified example

Enabling the setting and creating a test agent produced this row (~5–15 min ingestion delay):

| Time (UTC) | Operation | Result | Caller object ID |
| --- | --- | --- | --- |
| 2026‑08‑27 07:32:14 | `Projects_Wildcard_Post` | 200 | `<CallerObjectId>` |

`az ad user show --id <CallerObjectId>` → **<Display Name>
(`<user@tenant.onmicrosoft.com>`)** — i.e. the person who created the agent.

## Caveats

- **Generic operation names.** Agent operations log as `Projects_Wildcard_Post` /
  `Projects_Wildcard_Delete` (not "CreateAgent"), and the **agent name is not in the log body**.
  Attribute by **caller object ID + timestamp**, then correlate to the agent by creation time.
- **Object ID, not name.** The log stores the Entra `objectId`; resolve to a name with one lookup.
- **Ingestion latency.** First events take ~5–15 minutes to appear.
- **Retroactive gap.** Agents created before logging was enabled have no recorded author.
