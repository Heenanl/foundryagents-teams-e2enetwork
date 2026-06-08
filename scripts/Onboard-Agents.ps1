<#
.SYNOPSIS
    Reconciler: repoint Foundry-published bots to the APIM bridge.

.DESCRIPTION
    Foundry's one-click Teams publish creates an Azure Bot whose messaging endpoint
    points at the PRIVATE Foundry host (unreachable by public Azure Bot Service).
    This script finds those bots and rewrites the endpoint to route through APIM,
    preserving each agent's unique path and the api-version Foundry set.

    Idempotent: bots already pointing at APIM are skipped. Safe to run repeatedly
    or on a schedule (e.g. an Azure Automation runbook).

    IMPORTANT: Foundry-published bots are NOT returned by 'az bot list'. This script
    enumerates them via the generic resource API (Microsoft.BotService/botServices).

.PARAMETER ResourceGroup
    Resource group containing the bots and APIM.

.PARAMETER ApimGateway
    APIM gateway URL (e.g. https://apim-foundry-bridge.azure-api.net). If omitted,
    it is resolved from -ApimName.

.PARAMETER ApimName
    APIM service name (used to resolve the gateway URL when -ApimGateway is omitted).

.PARAMETER ApiPath
    APIM API path prefix. Default 'foundry'.

.PARAMETER FallbackApiVersion
    api-version to use only if a bot endpoint has no query string. Default '2025-11-15-preview'.

.PARAMETER WhatIf
    Show which bots would be repointed without applying changes.

.EXAMPLE
    ./Onboard-Agents.ps1 -ResourceGroup rg-foundry-privateagent -ApimName apim-foundry-bridge

.EXAMPLE
    ./Onboard-Agents.ps1 -ResourceGroup rg-foundry-privateagent -ApimName apim-foundry-bridge -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$ApimGateway,

    [string]$ApimName,

    [string]$ApiPath = 'foundry',

    [string]$FallbackApiVersion = '2025-11-15-preview',

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$BOT_API_VER = '2022-09-15'
$ARM_API_VER = '2024-05-01'
$foundryHostPattern = '^https://[^/]+\.services\.ai\.azure\.com'

function Write-Info([string]$m) { Write-Host $m -ForegroundColor Cyan }

# Resolve the APIM gateway URL if not supplied
if (-not $ApimGateway) {
    if (-not $ApimName) { throw 'Provide either -ApimGateway or -ApimName.' }
    $sub = az account show --query id -o tsv
    $ApimGateway = az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$($ApimName)?api-version=$ARM_API_VER" `
        --query 'properties.gatewayUrl' -o tsv 2>$null
    if (-not $ApimGateway) { throw "Could not resolve gateway URL for APIM '$ApimName'." }
}
$ApimGateway = $ApimGateway.TrimEnd('/')
$apimPrefix  = "$ApimGateway/$ApiPath"

Write-Info "==> Scanning Foundry bots in '$ResourceGroup'"
$bots = az resource list --resource-group $ResourceGroup --resource-type 'Microsoft.BotService/botServices' `
    --query '[].{name:name, id:id}' -o json 2>$null | ConvertFrom-Json
if (-not $bots) { Write-Host '    No bots found.'; return }

$changed = 0
$skipped = 0
foreach ($b in $bots) {
    $bot = az resource show --ids $b.id --api-version $BOT_API_VER -o json 2>$null | ConvertFrom-Json
    $ep = $bot.properties.endpoint
    if (-not $ep) { Write-Host "    [skip] $($b.name) has no endpoint" -ForegroundColor DarkGray; $skipped++; continue }

    if ($ep -like "$ApimGateway*") {
        Write-Host "    [ok]   $($b.name) already via APIM" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if ($ep -match $foundryHostPattern) {
        # Preserve Foundry's exact path AND query (incl. its api-version).
        # Only fall back to the default if Foundry omitted the query string.
        $uri   = [System.Uri]$ep
        $query = $uri.Query
        if (-not $query) { $query = "?api-version=$FallbackApiVersion" }
        $newEp = "$apimPrefix$($uri.AbsolutePath)$query"

        Write-Host "    [fix]  $($b.name)" -ForegroundColor Yellow
        Write-Host "           from: $ep"
        Write-Host "           to  : $newEp"

        if (-not $WhatIf) {
            az resource update --ids $b.id --api-version $BOT_API_VER --set properties.endpoint=$newEp --output none
            if ($LASTEXITCODE -ne 0) { throw "Failed to update endpoint for $($b.name)" }
            Write-Host '           [updated]' -ForegroundColor Green
        }
        $changed++
    }
    else {
        Write-Host "    [skip] $($b.name) endpoint not Foundry-private" -ForegroundColor DarkGray
        $skipped++
    }
}

Write-Host ''
Write-Host "Done. Repointed: $changed   Skipped: $skipped" -ForegroundColor Green
if ($WhatIf -and $changed -gt 0) { Write-Host '(WhatIf mode — no changes applied)' -ForegroundColor Yellow }
