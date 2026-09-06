<#
.SYNOPSIS
  Registers the Entra app for the MCP-OBO gateway and wires it for both Foundry OAuth2 passthrough
  and local end-to-end validation.

  Creates:
    - App registration "mcp-obo-gateway" with Application ID URI api://<appId>
    - Exposed delegated scope: access_as_user  (what Foundry requests / the gateway requires)
    - Delegated Microsoft Graph perms: Files.Read.All, Sites.Read.All, User.Read  (+ admin consent)
    - Pre-authorized Azure CLI client, so `az account get-access-token --scope api://<appId>/access_as_user`
      yields a real per-user token for browser-free validation (mimics Foundry's forwarded token)
    - A client secret (dev). For production use the secret-less federated path instead.

.NOTES
  Requires an Entra admin (this account: admin@...). Idempotent-ish: re-run reuses the app if present.
#>
[CmdletBinding()]
param(
  [string]$DisplayName = "mcp-obo-gateway"
)
$ErrorActionPreference = "Stop"

$graph        = "00000003-0000-0000-c000-000000000000"
$FilesReadAll = "df85f4d6-205c-4ac5-a5ea-6bf408dba283"   # delegated
$SitesReadAll = "205e70e5-aba6-4c52-a976-6d2d46c48043"   # delegated
$UserRead     = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"   # delegated
$azCli        = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"   # Azure CLI public client

Write-Host "Tenant:" (az account show --query tenantId -o tsv)

# Helper: PATCH the application via Graph using a temp JSON file (reliable quoting on PowerShell).
function Patch-App([string]$oid, $bodyObj) {
  $f = New-TemporaryFile
  ($bodyObj | ConvertTo-Json -Depth 10) | Set-Content -Path $f -Encoding utf8
  az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$oid" `
    --headers "Content-Type=application/json" --body "@$f" | Out-Null
  Remove-Item $f -Force
}

# 1) Create (or reuse) the app.
$existing = az ad app list --display-name $DisplayName --query "[0].appId" -o tsv
if ($existing) {
  Write-Host "Reusing existing app $existing"
  $appId = $existing
} else {
  $appId = az ad app create --display-name $DisplayName --query appId -o tsv
  Write-Host "Created app $appId"
}
$objectId = az ad app show --id $appId --query id -o tsv

# 2) Set the Graph delegated permissions (requiredResourceAccess) via an explicit PATCH so it is
#    guaranteed on both the create and reuse paths. A missing/malformed block here is what causes
#    AADSTS1003031 "Misconfigured required resource access" on the consent page.
Patch-App $objectId @{
  requiredResourceAccess = @(@{
    resourceAppId  = $graph
    resourceAccess = @(
      @{ id = $FilesReadAll; type = "Scope" },
      @{ id = $SitesReadAll; type = "Scope" },
      @{ id = $UserRead;     type = "Scope" }
    )
  })
}
Write-Host "Set Graph delegated permissions (Files.Read.All, Sites.Read.All, User.Read)"

# 3) Set the Application ID URI and expose the access_as_user scope.
#    Reuse the scope id if the scope already exists, otherwise mint one.
$scopeId = az ad app show --id $appId --query "api.oauth2PermissionScopes[?value=='access_as_user'].id | [0]" -o tsv
if (-not $scopeId) { $scopeId = [guid]::NewGuid().ToString() }
Patch-App $objectId @{
  identifierUris = @("api://$appId")
  api = @{
    # v2 tokens so the issuer is login.microsoftonline.com/<tenant>/v2.0 (what AzureJWTVerifier expects).
    requestedAccessTokenVersion = 2
    oauth2PermissionScopes = @(@{
      id                      = $scopeId
      value                   = "access_as_user"
      type                    = "User"
      isEnabled               = $true
      adminConsentDisplayName = "Access the MCP-OBO gateway as the signed-in user"
      adminConsentDescription = "Allows the gateway to call downstream APIs on behalf of the user."
      userConsentDisplayName  = "Access the gateway on your behalf"
      userConsentDescription  = "Allows the gateway to act on your behalf."
    })
  }
}
Write-Host "Exposed scope access_as_user ($scopeId)"

# 4) Pre-authorize the Azure CLI for that scope. This is a SEPARATE PATCH: preAuthorizedApplications
#    is validated against scopes that already exist, so it must run after the scope is created.
Patch-App $objectId @{
  api = @{ preAuthorizedApplications = @(@{ appId = $azCli; delegatedPermissionIds = @($scopeId) }) }
}
Write-Host "Pre-authorized Azure CLI for browser-free validation"

# 5) Service principal + admin consent for the Graph delegated permissions.
if (-not (az ad sp show --id $appId --query id -o tsv 2>$null)) { az ad sp create --id $appId | Out-Null }
az ad app permission admin-consent --id $appId
Write-Host "Admin consent granted"

# 6) Client secret (dev path).
$secret = az ad app credential reset --id $appId --display-name "gateway-obo" --query password -o tsv

Write-Host ""
Write-Host "===== gateway .env values =====" -ForegroundColor Green
Write-Host "GATEWAY_TENANT_ID=$(az account show --query tenantId -o tsv)"
Write-Host "GATEWAY_CLIENT_ID=$appId"
Write-Host "GATEWAY_CLIENT_SECRET=$secret"
Write-Host "REQUIRED_SCOPES=access_as_user"
Write-Host "APP_ID_URI=api://$appId"
Write-Host "==============================="
