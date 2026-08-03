<#
.SYNOPSIS
    Publish a private-networked Foundry agent to Microsoft Teams / Microsoft 365
    Copilot via the REST API, and point its Azure Bot at the APIM bridge.

.DESCRIPTION
    Foundry has REMOVED the one-click "Publish to Teams" button for projects with
    private networking (public network access disabled). This script performs the
    supported REST-API replacement, then wires the resulting bot to the APIM bridge
    so Microsoft's Bot Channel Adapters can reach the private agent.

    Steps (per the official guidance):
      1. Get the agent identity principal ID (Foundry Get agent API) and tenant ID.
      2. Create/refresh the Azure Bot Service resource + Teams channel
         (infra/bot-service.bicep) with its endpoint pointed at the APIM bridge.
      3. (Automatic in step 4) Enable the activity protocol + Bot Service auth scheme.
      4. Call Foundry's Microsoft 365 publish API.
    Step 5 (inbound networking) is already provided by the APIM bridge in this repo.

    Idempotent: re-running updates the same bot. Republishing the SAME AppVersion is
    rejected by Foundry (increment -AppVersion to change user-facing metadata).

    Ref: https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network

.PARAMETER ResourceGroup
    Resource group that holds the private Foundry deployment and the APIM bridge.
    The bot is created here too.

.PARAMETER AgentName
    Name of the Foundry agent to publish (as shown in the Foundry portal).

.PARAMETER ProjectEndpoint
    Full Foundry project endpoint, e.g.
    https://<account>.services.ai.azure.com/api/projects/<project>.
    Alternatively supply -FoundryHost and -ProjectName.

.PARAMETER FoundryHost
    Foundry account host, e.g. https://<account>.services.ai.azure.com
    (used with -ProjectName when -ProjectEndpoint is omitted).

.PARAMETER ProjectName
    Foundry project name (used with -FoundryHost).

.PARAMETER ApimGateway
    APIM gateway URL, e.g. https://apim-foundry-bridge.azure-api.net. If omitted,
    it is resolved from -ApimName. If neither is given, the bot endpoint is left on
    the private Foundry host and you must run scripts/Onboard-Agents.ps1 afterwards.

.PARAMETER ApimName
    APIM service name (used to resolve the gateway URL when -ApimGateway is omitted).

.PARAMETER ApiPath
    APIM API path prefix. Default 'foundry'.

.PARAMETER FoundryApiVersion
    Activity-protocol api-version stamped on the bot endpoint. Default '2025-11-15-preview'.

.PARAMETER BotName
    Azure Bot resource name. Default: a sanitized form of the agent name.

.PARAMETER DisplayName
    Display name shown in Teams / Microsoft 365 Copilot. Default: the agent name.

.PARAMETER PublishScope
    Shared (just you), Tenant (whole org, needs admin approval), or Personal
    (treated as Shared). Default 'Shared'.

.PARAMETER AppVersion
    Semantic version of the Teams app manifest (digits and periods only, cannot
    start with 0). Increment to change user-facing metadata. Default '1.0.0'.

.PARAMETER ShortDescription
.PARAMETER FullDescription
.PARAMETER DeveloperName
.PARAMETER DeveloperWebsiteUrl
.PARAMETER PrivacyUrl
.PARAMETER TermsOfUseUrl
    Store metadata shown to users. Do NOT put secrets in these fields.

.PARAMETER SkipPublish
    Create/refresh the bot only; do not call the Microsoft 365 publish API.

.PARAMETER WhatIf
    Show what would happen without creating the bot or publishing.

.EXAMPLE
    ./Publish-AgentToTeams.ps1 -ResourceGroup rg-foundry-privateagent `
        -AgentName contoso-support-agent `
        -ProjectEndpoint https://aiservicesktdp.services.ai.azure.com/api/projects/projectktdp `
        -ApimName apim-foundry-bridge

.EXAMPLE
    ./Publish-AgentToTeams.ps1 -ResourceGroup rg-foundry-privateagent `
        -AgentName contoso-support-agent -FoundryHost https://aiservicesktdp.services.ai.azure.com `
        -ProjectName projectktdp -ApimName apim-foundry-bridge -PublishScope Tenant -AppVersion 1.0.1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$AgentName,

    [string]$ProjectEndpoint,
    [string]$FoundryHost,
    [string]$ProjectName,

    [string]$ApimGateway,
    [string]$ApimName,
    [string]$ApiPath = 'foundry',
    [string]$FoundryApiVersion = '2025-11-15-preview',

    [string]$BotName,
    [string]$DisplayName,

    [ValidateSet('Shared', 'Tenant', 'Personal')]
    [string]$PublishScope = 'Shared',

    [ValidatePattern('^[1-9][0-9]*(\.[0-9]+)*$')]
    [string]$AppVersion = '1.0.0',

    [string]$ShortDescription   = 'Foundry M365 Agent',
    [string]$FullDescription    = 'A Foundry agent published to Microsoft 365 and Teams.',
    [string]$DeveloperName      = 'Platform Team',
    [string]$DeveloperWebsiteUrl = 'https://azure.microsoft.com',
    [string]$PrivacyUrl         = 'https://privacy.microsoft.com',
    [string]$TermsOfUseUrl      = 'https://www.microsoft.com/legal/terms-of-use',

    [switch]$SkipPublish,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$ARM_API_VER = '2024-05-01'
$AI_RESOURCE = 'https://ai.azure.com'
$botTemplate = Join-Path $PSScriptRoot '../infra/bot-service.bicep'

function Write-Info([string]$m) { Write-Host $m -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host "    [OK] $m" -ForegroundColor Green }

# ── Resolve the project endpoint (host + project) ─────────────────────────────
if (-not $ProjectEndpoint) {
    if (-not $FoundryHost -or -not $ProjectName) {
        throw 'Provide -ProjectEndpoint, or both -FoundryHost and -ProjectName.'
    }
    $ProjectEndpoint = "$($FoundryHost.TrimEnd('/'))/api/projects/$ProjectName"
}
$ProjectEndpoint = $ProjectEndpoint.TrimEnd('/')

if ($ProjectEndpoint -notmatch '^(https://[^/]+)/api/projects/([^/?]+)') {
    throw "ProjectEndpoint '$ProjectEndpoint' is not of the form https://<account>.services.ai.azure.com/api/projects/<project>."
}
$resolvedHost = $Matches[1]
$project      = $Matches[2]

# ── Resolve the APIM gateway (optional) ───────────────────────────────────────
if (-not $ApimGateway -and $ApimName) {
    $sub = az account show --query id -o tsv
    $ApimGateway = az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$($ApimName)?api-version=$ARM_API_VER" `
        --query 'properties.gatewayUrl' -o tsv 2>$null
    if (-not $ApimGateway) { throw "Could not resolve gateway URL for APIM '$ApimName'." }
}

# ── Build the bot messaging endpoint ──────────────────────────────────────────
$activityPath = "/api/projects/$project/agents/$AgentName/endpoint/protocols/activityprotocol?api-version=$FoundryApiVersion"
if ($ApimGateway) {
    $ApimGateway = $ApimGateway.TrimEnd('/')
    $botEndpoint = "$ApimGateway/$ApiPath$activityPath"
    $routing     = "APIM bridge ($ApimGateway)"
}
else {
    $botEndpoint = "$resolvedHost$activityPath"
    $routing     = 'private Foundry host (run Onboard-Agents.ps1 afterwards)'
}

# ── Defaults derived from the agent ───────────────────────────────────────────
if (-not $DisplayName) { $DisplayName = $AgentName }
if (-not $BotName) {
    $clean = ($AgentName -replace '[^a-zA-Z0-9-]', '-').Trim('-')
    if ($clean.Length -gt 42) { $clean = $clean.Substring(0, 42).Trim('-') }
    $BotName = $clean
}

# ── Step 1: agent identity principal ID + tenant ID ───────────────────────────
Write-Info "==> Reading agent identity for '$AgentName'"
$agentUrl = "$ProjectEndpoint/agents/$AgentName`?api-version=v1"
# The Foundry data-plane firewall can transiently return 403 ("Access denied due to
# Virtual Network/Firewall rules") even when your IP is allowlisted, so retry briefly.
$agent = $null
$maxAttempts = 12
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $raw = az rest --method GET --url $agentUrl --resource $AI_RESOURCE -o json 2>&1
    if ($LASTEXITCODE -eq 0) {
        $agent = $raw | ConvertFrom-Json
        break
    }
    if ("$raw" -match '403|Virtual Network/Firewall') {
        Write-Host "    [retry $attempt/$maxAttempts] firewall denied; waiting for an allow window..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        continue
    }
    throw "Failed to read agent '$AgentName' from $ProjectEndpoint`n$raw"
}
if (-not $agent) { throw "Failed to read agent '$AgentName' after $maxAttempts attempts (Foundry firewall never allowed the request). Confirm publicNetworkAccess=Enabled and your IP is allowlisted, then retry." }

$principalId = $agent.instance_identity.principal_id
if (-not $principalId) {
    throw "Agent '$AgentName' has no unique identity (instance_identity.principal_id is null). See the Foundry agent migration guide."
}
$tenantId = az account show --query tenantId -o tsv
Write-OK "principalId $principalId | tenant $tenantId"

# ── Plan summary ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "  Agent        : $AgentName ($project)" -ForegroundColor White
Write-Host "  Bot name     : $BotName" -ForegroundColor White
Write-Host "  Display name : $DisplayName" -ForegroundColor White
Write-Host "  Endpoint     : $botEndpoint" -ForegroundColor White
Write-Host "  Routing      : $routing" -ForegroundColor White
Write-Host "  Publish scope: $PublishScope   App version: $AppVersion" -ForegroundColor White
Write-Host ''

if ($WhatIf) {
    Write-Host '(WhatIf) No bot created and nothing published.' -ForegroundColor Yellow
    return
}

# ── Step 2: create/refresh the Azure Bot Service + Teams channel ──────────────
Write-Info '==> Registering Microsoft.BotService provider (idempotent)'
az provider register --namespace Microsoft.BotService --output none

Write-Info "==> Deploying bot '$BotName'"
$deploymentName = "publish-bot-$BotName-$(Get-Date -Format 'yyyyMMddHHmmss')"
az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroup `
    --template-file $botTemplate `
    --parameters `
        botName=$BotName `
        displayName=$DisplayName `
        msaAppId=$principalId `
        tenantId=$tenantId `
        endpoint=$botEndpoint `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Bot deployment failed for '$BotName'." }

$botServiceArmId = az deployment group show --resource-group $ResourceGroup --name $deploymentName `
    --query 'properties.outputs.botServiceArmId.value' -o tsv
if (-not $botServiceArmId) { throw 'Could not read botServiceArmId from the deployment outputs.' }
Write-OK "Bot ready: $botServiceArmId"

if ($SkipPublish) {
    Write-Host ''
    Write-Host 'Bot created. Skipping the Microsoft 365 publish call (-SkipPublish).' -ForegroundColor Yellow
    return
}

# ── Step 4: publish the agent to Microsoft 365 / Teams ────────────────────────
Write-Info '==> Publishing to Microsoft 365 / Teams'
$publishBody = [ordered]@{
    agentDisplayName    = $DisplayName
    botServiceArmId     = $botServiceArmId
    publishScope        = $PublishScope
    publishAsAutopilot  = $false
    appVersion          = $AppVersion
    shortDescription    = $ShortDescription
    fullDescription     = $FullDescription
    developerName       = $DeveloperName
    developerWebsiteUrl = $DeveloperWebsiteUrl
    privacyUrl          = $PrivacyUrl
    termsOfUseUrl       = $TermsOfUseUrl
} | ConvertTo-Json

# Write without a BOM (az rest rejects a UTF-8 BOM: "Unexpected UTF-8 BOM").
$tmp = New-TemporaryFile
try {
    [System.IO.File]::WriteAllText($tmp.FullName, $publishBody, (New-Object System.Text.UTF8Encoding($false)))

    $publishUrl = "$ProjectEndpoint/agents/$AgentName/microsoft365/publish`?api-version=v1"
    # Same transient-firewall retry as the identity read.
    $result = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $raw = az rest --method POST --url $publishUrl --resource $AI_RESOURCE `
            --headers 'Content-Type=application/json' `
            --body "@$($tmp.FullName)" -o json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result = $raw | ConvertFrom-Json
            break
        }
        if ("$raw" -match '403|Virtual Network/Firewall') {
            Write-Host "    [retry $attempt/$maxAttempts] firewall denied; waiting for an allow window..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
            continue
        }
        throw "Publish call failed.`n$raw`nFix any metadata error and increment -AppVersion if this version already exists."
    }
    if (-not $result) { throw "Publish call never got through the Foundry firewall after $maxAttempts attempts." }
}
finally {
    Remove-Item $tmp.FullName -ErrorAction SilentlyContinue
}

$titleId = $result.titleId
Write-OK "Published. titleId: $titleId"

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '─────────────────────────────────────────────────────────' -ForegroundColor White
Write-Host " Agent '$AgentName' published to Microsoft 365 / Teams" -ForegroundColor Green
Write-Host '─────────────────────────────────────────────────────────' -ForegroundColor White
Write-Host " Bot          : $BotName" -ForegroundColor White
Write-Host " Endpoint     : $botEndpoint" -ForegroundColor White
Write-Host " Publish scope: $PublishScope" -ForegroundColor White
if ($PublishScope -eq 'Tenant') {
    Write-Host ' Next         : a Microsoft 365 admin must approve it in the M365 admin center' -ForegroundColor Yellow
}
if (-not $ApimGateway) {
    Write-Host ' Next         : run ./deploy.ps1 -OnboardOnly to route the bot through the APIM bridge' -ForegroundColor Yellow
}
Write-Host " Find it in the agent store (~1 hr cache): Shared -> 'Your agents', Tenant -> 'Built by your org'." -ForegroundColor White
