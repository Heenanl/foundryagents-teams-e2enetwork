<#
.SYNOPSIS
    Creates/configures the Entra app registration for the Teams SSO bot:
    - delegated Microsoft Graph: Files.Read.All, Sites.Read.All, User.Read, openid, profile, offline_access
    - exposes an API (Application ID URI api://botid-<appId>) with an access_as_user scope
    - pre-authorizes the Teams client apps (silent SSO)
    - creates a client secret

.NOTES
    Requires: az CLI signed in with rights to create app registrations. A Global Administrator must
    GRANT ADMIN CONSENT for the Graph delegated permissions afterward (link printed at the end).

.EXAMPLE
    ./Register-SsoApp.ps1 -DisplayName "SharePoint KB Bot"
#>
[CmdletBinding()]
param(
    [string]$DisplayName = "SharePoint KB Teams SSO Bot"
)
$ErrorActionPreference = "Stop"

# Microsoft Graph well-known IDs
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$Delegated = @{
    "Files.Read.All"  = "df85f4d6-205c-4ac5-a5ea-6bf408dba283"
    "Sites.Read.All"  = "205e70e5-aba6-4c52-a976-6d2d46c48043"
    "User.Read"       = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
    "openid"          = "37f7f235-527c-4136-accd-4a02d197296e"
    "profile"         = "14dad69e-099b-42c9-810b-d002981feec1"
    "offline_access"  = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"
}
# Teams first-party client app IDs pre-authorized for silent SSO (add Office IDs if you surface as a tab too).
$TeamsClientIds = @(
    "1fec8e78-bce4-4aaf-ab1b-5451cc387264",  # Teams desktop / mobile
    "5e3ce6c0-2b1f-4285-8d4b-75ee78787346"   # Teams web
)

Write-Host "Creating app registration '$DisplayName'..." -ForegroundColor Cyan
$appId = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg --query appId -o tsv
$objectId = az ad app show --id $appId --query id -o tsv
Write-Host "  appId=$appId"

# Delegated Graph permissions
$resourceAccess = ($Delegated.Values | ForEach-Object { @{ id = $_; type = "Scope" } })
$requiredResourceAccess = @(@{ resourceAppId = $GraphAppId; resourceAccess = $resourceAccess })

# Expose API + access_as_user scope + pre-authorized Teams clients
$identifierUri = "api://botid-$appId"
$scopeId = [guid]::NewGuid().ToString()
$apiPatch = @{
    identifierUris         = @($identifierUri)
    requiredResourceAccess = $requiredResourceAccess
    api                    = @{
        oauth2PermissionScopes  = @(@{
                id                      = $scopeId
                adminConsentDisplayName = "Access as user"
                adminConsentDescription = "Allows the bot to access the API as the signed-in user."
                userConsentDisplayName  = "Access as you"
                userConsentDescription  = "Allows the bot to access on your behalf."
                value                   = "access_as_user"
                type                    = "User"
                isEnabled               = $true
            })
        preAuthorizedApplications = ($TeamsClientIds | ForEach-Object {
                @{ appId = $_; delegatedPermissionIds = @($scopeId) }
            })
    }
} | ConvertTo-Json -Depth 8
$apiPatch | Out-File "$env:TEMP\ssoapp-patch.json" -Encoding utf8
Write-Host "Configuring API, scopes, Graph permissions, pre-authorized Teams clients..." -ForegroundColor Cyan
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objectId" `
    --headers "Content-Type=application/json" --body "@$env:TEMP\ssoapp-patch.json"
Remove-Item "$env:TEMP\ssoapp-patch.json" -ErrorAction SilentlyContinue

Write-Host "Creating client secret..." -ForegroundColor Cyan
$secret = az ad app credential reset --id $appId --display-name "bot-secret" --query password -o tsv
$tenantId = az account show --query tenantId -o tsv

Write-Host "`n==================== SAVE THESE ====================" -ForegroundColor Green
Write-Host "MicrosoftAppId        = $appId"
Write-Host "MicrosoftAppPassword  = $secret   (store securely; not shown again)"
Write-Host "MicrosoftAppTenantId  = $tenantId"
Write-Host "Application ID URI     = $identifierUri   (manifest webApplicationInfo.resource)"
Write-Host "===================================================" -ForegroundColor Green
Write-Host "`nNEXT (Global Admin):" -ForegroundColor Yellow
Write-Host "  1. Grant admin consent for the Graph delegated permissions:"
Write-Host "     https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$appId"
Write-Host "  2. Create the Azure Bot registration with msaAppId=$appId (see ../README.md)."
Write-Host "  3. Add an OAuth connection on the bot (name it e.g. 'graph') using the Azure AD v2"
Write-Host "     provider, this app's id/secret, tenant, and scopes: Files.Read.All Sites.Read.All openid profile offline_access."
