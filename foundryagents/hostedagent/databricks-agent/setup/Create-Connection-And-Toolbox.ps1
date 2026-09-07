<#
.SYNOPSIS
  Creates the Foundry OAuth2 identity-passthrough CONNECTION to the Azure Databricks Genie MCP server
  and the TOOLBOX that wraps it — via code (no portal clicks). Mirrors the official Foundry sample:
  https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/SUPPORTED_TOOLBOX_SCENARIOS/tools/mcp-oauth-custom.md

  Databricks is a THIRD-PARTY OAuth provider, so this uses the Databricks workspace authorize/token
  URLs and scopes (NOT Entra's). After the connection exists, Foundry mints a reply URL that you must
  register on the DATABRICKS OAuth app (this script prints it — Databricks redirect registration is
  done in the Databricks account console, not via az).

  Steps performed:
    1. azd ai connection create (kind remote-tool, auth-type oauth2) -> AzureDatabricksGenieOBO
    2. Read + print the per-connection reply URL (register it on the Databricks OAuth app yourself)
    3. azd ai toolbox create databricks-tools --from-file toolbox.yaml

.NOTES
  Requires: az login (correct tenant), azd >= 1.27.1 with `azd ext install microsoft.foundry`.
  A Databricks custom OAuth app (client id + secret) and a Genie space must already exist.
  Confirm the authorize/token URLs and scope for YOUR workspace before relying on the defaults.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ProjectEndpoint,          # https://<account>.services.ai.azure.com/api/projects/<project>
  [Parameter(Mandatory)][string]$WorkspaceHost,            # e.g. adb-1234567890.11.azuredatabricks.net
  [Parameter(Mandatory)][string]$GenieSpaceId,             # Genie space id
  [Parameter(Mandatory)][string]$DatabricksClientId,       # Databricks custom OAuth app client id
  [Parameter(Mandatory)][string]$DatabricksClientSecret,   # Databricks custom OAuth app secret
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$ResourceGroup,
  [Parameter(Mandatory)][string]$AccountName,              # Foundry (AI Services) account name
  [Parameter(Mandatory)][string]$ProjectName,
  [string]$ConnectionName = "AzureDatabricksGenieOBO",
  [string]$ToolboxName = "databricks-tools",
  [string]$ToolboxFile = (Join-Path $PSScriptRoot "..\agent-framework-agent-with-foundry-toolbox-responses\toolbox.yaml"),
  # Databricks OAuth endpoints/scope — verify these for your workspace.
  [string]$AuthorizationUrl = "https://$($WorkspaceHost)/oidc/v1/authorize",
  [string]$TokenUrl = "https://$($WorkspaceHost)/oidc/v1/token",
  [string]$Scopes = "all-apis,offline_access"
)
$ErrorActionPreference = "Stop"

$target = "https://$WorkspaceHost/api/2.0/mcp/genie/$GenieSpaceId"

# 1) Create the OAuth2 identity-passthrough connection (offline_access lets Foundry auto-refresh).
Write-Host "Creating connection $ConnectionName -> $target ..."
azd ai connection create $ConnectionName `
  --kind remote-tool `
  --target $target `
  --auth-type oauth2 `
  --client-id $DatabricksClientId `
  --client-secret $DatabricksClientSecret `
  --authorization-url $AuthorizationUrl `
  --token-url $TokenUrl `
  --scopes $Scopes `
  --project-endpoint $ProjectEndpoint

# 2) Read the reply URL Foundry generated for this connection (register it on the DATABRICKS OAuth app).
$connUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$AccountName/projects/$ProjectName/connections/$ConnectionName?api-version=2025-06-01"
$replyUrl = az rest --method get --url $connUrl --query "properties.redirectUrl" -o tsv
if (-not $replyUrl) { throw "Could not read the connection reply URL from $connUrl" }
Write-Host ""
Write-Host "ACTION REQUIRED — register this reply URL as a redirect URI on your Databricks OAuth app:" -ForegroundColor Yellow
Write-Host "  $replyUrl"
Write-Host "(Databricks account console > Settings > App connections > your OAuth app > Redirect URLs)"
Write-Host ""

# 3) Create the toolbox that wraps the connection.
Write-Host "Creating toolbox $ToolboxName from $ToolboxFile ..."
azd ai toolbox create $ToolboxName --from-file $ToolboxFile --project-endpoint $ProjectEndpoint

Write-Host ""
Write-Host "===== done =====" -ForegroundColor Green
Write-Host "Connection : $ConnectionName"
Write-Host "Toolbox    : $ToolboxName"
Write-Host "Next: register the reply URL above on the Databricks OAuth app, deploy the agent (README step 3),"
Write-Host "      then invoke and complete the one-time Databricks sign-in/consent."
