# SharePoint / enterprise-data grounding options for Foundry agents

How each grounding option behaves across prompt and hosted agents.
Legend: ✅ supported, ❌ not supported, ⚠️ partial, 🧪 preview.

| # | Tool / route | Backed by | Prompt | Hosted | Teams | Per-user (trimmed) | Scoping | Licensing | Repo sample |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | SharePoint grounding tool (`sharepoint_grounding_preview`) 🧪 | Copilot Retrieval API | ✅ | ❌ (app-only) | ✅ as prompt, ❌ hosted | ✅ | one site/folder | Copilot license or Retrieval API paygo | `promptagent/sharepoint-agent-grounding-tool` |
| 2 | Work IQ (`work_iq_preview`) 🧪 | Work IQ over M365 | ✅ | ✅ | ✅ | ✅ | none (broad M365) | Copilot license or Work IQ paygo | `hostedagent/sharepoint-agent-workiq` |
| 3 | Databricks Genie (remote MCP) 🧪 | Databricks Genie | ✅ | ✅ | ✅ | ⚠️ shared token, not per-user | Genie space | Databricks | `hostedagent/databricks-agent` |
| 4 | MCP-OBO gateway (Retrieval API) 🧪 | Copilot Retrieval API | ✅ | ✅ | ✅ | ✅ | site / path / file type / date | Copilot license or Retrieval API paygo | `mcp-obo-gateway` + `hostedagent/sharepoint-agent-copilot-retrieval` |
| 5 | Basic prompt agent (model only) | model deployment | ✅ | n/a | via publish | n/a | n/a | model only | `promptagent` |

## What decides the outcome

Identity: a prompt agent runs as the signed-in user (OBO); a hosted container runs as its own managed
identity (app-only). A hosted agent gets per-user access only when Foundry brokers the user's token
through an OAuth2 identity-passthrough connection (rows 2, 3, 4). This is why the native SharePoint
grounding tool works in a prompt agent but is rejected app-only in a hosted one.

Scoping: only the SharePoint grounding tool (site/folder) and the Retrieval API filter expression
(site, path, file type, date) scope to a single site. Work IQ reasons over broad M365 and does not
scope per site.

## For hosted + Teams

Work IQ, Databricks Genie, and the MCP-OBO gateway all run from a hosted agent on the Foundry auto-bot,
because they use OAuth2 identity-passthrough where Foundry brokers the per-user token. The MCP-OBO
gateway applies that to the Copilot Retrieval API with site scoping. See
[../foundryagents/mcp-obo-gateway/README.md](../foundryagents/mcp-obo-gateway/README.md).
