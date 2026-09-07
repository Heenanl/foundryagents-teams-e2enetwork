<#
.SYNOPSIS
  Creates the Foundry OAuth2 identity-passthrough CONNECTION to the MCP-OBO gateway and the TOOLBOX
  that wraps it — entirely via code (no portal clicks). Mirrors the official Foundry sample:
  https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/SUPPORTED_TOOLBOX_SCENARIOS/tools/mcp-oauth-custom.md

  Steps performed:
    1. azd ai connection create (kind remote-tool, auth-type oauth2) -> SharePointRetrievalOBO
    2. Read the per-connection reply URL Foundry generated (ARM control plane)
    3. Register that reply URL on the gateway Entra app (append-safe) so consent doesn't fail
       with redirect_uri mismatch
    4. azd ai toolbox create sharepoint-retrieval-tools --from-file toolbox.yaml

.NOTES
  Requires: az login (correct tenant), azd >= 1.27.1 with `azd ext install microsoft.foundry`.
  The gateway must already be deployed (see ../../mcp-obo-gateway/README.md) and its Entra app
  registered (scripts/Register-GatewayApp.ps1).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ProjectEndpoint,          # https://<account>.services.ai.azure.com/api/projects/<project>
  [Parameter(Mandatory)][string]$GatewayHost,              # e.g. my-obo-gateway.azurewebsites.net
  [Parameter(Mandatory)][string]$GatewayAppId,             # gateway Entra app client id (Register-GatewayApp.ps1)
  [Parameter(Mandatory)][string]$GatewayClientSecret,      # gateway app secret
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$ResourceGroup,
  [Parameter(Mandatory)][string]$AccountName,              # Foundry (AI Services) account name
  [Parameter(Mandatory)][string]$ProjectName,
  [string]$TenantId = (az account show --query tenantId -o tsv),
  [string]$ConnectionName = "SharePointRetrievalOBO",
  [string]$ToolboxName = "sharepoint-retrieval-tools",
  [string]$ToolboxFile = (Join-Path $PSScriptRoot "..\agent-framework-agent-with-foundry-toolbox-responses\toolbox.yaml")
)
$ErrorActionPreference = "Stop"

$target = "https://$GatewayHost/mcp"
$authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize"
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
# offline_access lets Foundry auto-refresh the token (otherwise users re-consent on expiry).
$scopes = "api://$GatewayAppId/access_as_user,offline_access"

# 1) Create the OAuth2 identity-passthrough connection.
Write-Host "Creating connection $ConnectionName -> $target ..."
azd ai connection create $ConnectionName `
  --kind remote-tool `
  --target $target `
  --auth-type oauth2 `
  --client-id $GatewayAppId `
  --client-secret $GatewayClientSecret `
  --authorization-url $authUrl `
  --token-url $tokenUrl `
  --scopes $scopes `
  --project-endpoint $ProjectEndpoint

# 2) Read the reply URL Foundry generated for this connection (not surfaced by `azd ai connection show`).
$connUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$AccountName/projects/$ProjectName/connections/$ConnectionName?api-version=2025-06-01"
$replyUrl = az rest --method get --url $connUrl --query "properties.redirectUrl" -o tsv
if (-not $replyUrl) { throw "Could not read the connection reply URL from $connUrl" }
Write-Host "Foundry reply URL: $replyUrl"

# 3) Register the reply URL on the gateway app as a Web redirect URI (append-safe — az replaces the list).
$existing = az ad app show --id $GatewayAppId --query "web.redirectUris" -o json | ConvertFrom-Json
$all = @($existing) + $replyUrl | Where-Object { $_ } | Select-Object -Unique
az ad app update --id $GatewayAppId --web-redirect-uris @all
Write-Host "Registered reply URL on gateway app $GatewayAppId"

# 4) Create the toolbox that wraps the connection.
Write-Host "Creating toolbox $ToolboxName from $ToolboxFile ..."
azd ai toolbox create $ToolboxName --from-file $ToolboxFile --project-endpoint $ProjectEndpoint

Write-Host ""
Write-Host "===== done =====" -ForegroundColor Green
Write-Host "Connection : $ConnectionName"
Write-Host "Toolbox    : $ToolboxName"
Write-Host "Next: deploy the hosted agent (README step 3), then invoke and complete the one-time consent."
