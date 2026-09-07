<#
.SYNOPSIS
    Deploy the private-Foundry → Microsoft Teams APIM bridge.

.DESCRIPTION
    Deploys the Bicep infrastructure (subnet + NSG, APIM Standard v2 with VNet
    outbound integration, the templated bridge API and policy) into the existing
    resource group that hosts the private Foundry deployment, then onboards any
    Foundry-published bots by repointing them to the APIM gateway.

.PARAMETER SubscriptionId
    Target subscription. If omitted, the current az CLI subscription is used.

.PARAMETER WhatIf
    Run a Bicep what-if (no changes) and a dry-run onboarding.

.PARAMETER OnboardOnly
    Skip infrastructure; only repoint Foundry bots to the existing APIM bridge.
    Reconciler for bots created outside this repo. To publish a new agent from
    scratch (the Foundry portal button is gone for private projects), use
    scripts/Publish-AgentToTeams.ps1 instead.

.PARAMETER SkipOnboard
    Deploy infrastructure but do not run bot onboarding.

.PARAMETER ParametersFile
    Path to an alternate .bicepparam file (e.g. a clean test APIM). Defaults to
    infra/main.parameters.bicepparam.

.EXAMPLE
    ./deploy.ps1                     # full deploy + onboard
    ./deploy.ps1 -WhatIf             # preview infra + onboarding
    ./deploy.ps1 -OnboardOnly        # repoint bots only (after a new publish)

.EXAMPLE
    # Deploy a clean second APIM for end-to-end testing (no bot repointing):
    ./deploy.ps1 -ParametersFile infra/main.test.parameters.bicepparam -SkipOnboard
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [switch]$WhatIf,
    [switch]$OnboardOnly,
    [switch]$SkipOnboard,
    [string]$ParametersFile
)

$ErrorActionPreference = 'Stop'
$root          = $PSScriptRoot
$templateFile  = Join-Path $root 'infra/main.bicep'
$paramFile     = if ($ParametersFile) {
    if ([System.IO.Path]::IsPathRooted($ParametersFile)) { $ParametersFile } else { Join-Path $root $ParametersFile }
} else {
    Join-Path $root 'infra/main.parameters.bicepparam'
}
$rgConfigFile  = Join-Path $root 'infra/resourcegroup.config.json'
$onboardScript = Join-Path $root 'scripts/Onboard-Agents.ps1'

function Write-Step([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host "    [OK] $m" -ForegroundColor Green }

# ── Login / subscription ──────────────────────────────────────────────────────
Write-Step 'Checking Azure CLI login'
$acct = az account show -o json 2>$null | ConvertFrom-Json
if (-not $acct) { throw "Not logged in. Run 'az login' first." }
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
    $acct = az account show -o json | ConvertFrom-Json
}
Write-OK "Subscription: $($acct.name) ($($acct.id))"

# ── Read RG config ────────────────────────────────────────────────────────────
$rgConfig = Get-Content $rgConfigFile -Raw | ConvertFrom-Json
$RG       = $rgConfig.resourceGroupName
$LOCATION = $rgConfig.location

# Resolve APIM name from the bicepparam (for onboarding / output)
$apimName = (Select-String -Path $paramFile -Pattern "param\s+apimName\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
$apiPath  = (Select-String -Path $paramFile -Pattern "param\s+apiPath\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
if (-not $apiPath) { $apiPath = 'foundry' }

# ── Onboard-only fast path ────────────────────────────────────────────────────
if ($OnboardOnly) {
    & $onboardScript -ResourceGroup $RG -ApimName $apimName -ApiPath $apiPath -WhatIf:$WhatIf
    return
}

# ── Ensure resource group exists ──────────────────────────────────────────────
Write-Step "Ensuring resource group '$RG'"
az group create --name $RG --location $LOCATION --output none
Write-OK "Resource group ready"

# ── Deploy Bicep ──────────────────────────────────────────────────────────────
if ($WhatIf) {
    Write-Step 'Running Bicep what-if (no changes)'
    az deployment group what-if `
        --resource-group $RG `
        --template-file $templateFile `
        --parameters $paramFile
    Write-Step 'Dry-run onboarding'
    & $onboardScript -ResourceGroup $RG -ApimName $apimName -ApiPath $apiPath -WhatIf
    return
}

Write-Step 'Deploying bridge infrastructure (APIM provisioning can take ~10 min)'
$deploymentName = "foundry-teams-bridge-$(Get-Date -Format 'yyyyMMddHHmmss')"
az deployment group create `
    --name $deploymentName `
    --resource-group $RG `
    --template-file $templateFile `
    --parameters $paramFile `
    --output none
if ($LASTEXITCODE -ne 0) { throw 'Bicep deployment failed.' }
Write-OK 'Infrastructure deployed'

# ── Read outputs ──────────────────────────────────────────────────────────────
$outputs = az deployment group show --resource-group $RG --name $deploymentName --query 'properties.outputs' -o json | ConvertFrom-Json
$gatewayUrl = $outputs.apimGatewayUrl.value

# ── Onboard existing bots ─────────────────────────────────────────────────────
if (-not $SkipOnboard) {
    & $onboardScript -ResourceGroup $RG -ApimGateway $gatewayUrl -ApiPath $apiPath
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────' -ForegroundColor White
Write-Host ' Foundry → Teams private bridge deployed' -ForegroundColor Green
Write-Host '─────────────────────────────────────────────────────────' -ForegroundColor White
Write-Host " APIM gateway : $gatewayUrl" -ForegroundColor White
Write-Host " Endpoint     : $($outputs.endpointPattern.value)" -ForegroundColor White
Write-Host ''
Write-Host ' To publish an agent to Teams (the Foundry portal button is gone for' -ForegroundColor Yellow
Write-Host ' private-networking projects), create its bot + publish via the REST API:' -ForegroundColor Yellow
Write-Host "   ./scripts/Publish-AgentToTeams.ps1 -ResourceGroup $RG ``" -ForegroundColor Yellow
Write-Host "       -AgentName <agent> -ProjectEndpoint <project-endpoint> -ApimName $apimName" -ForegroundColor Yellow
Write-Host ''
Write-Host ' If an agent was created/published by other means, reconcile its bot to APIM:' -ForegroundColor Yellow
Write-Host '   ./deploy.ps1 -OnboardOnly' -ForegroundColor Yellow
