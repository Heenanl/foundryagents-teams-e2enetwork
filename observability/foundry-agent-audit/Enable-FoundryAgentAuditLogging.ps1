<#
.SYNOPSIS
    Enables data-plane audit logging on a Microsoft Foundry (Azure AI Services / Cognitive
    Services) account so that agent create / update / delete operations are attributable to a
    person (the caller's Entra object ID).

.DESCRIPTION
    Foundry agents are created through the project DATA plane, not Azure Resource Manager, so
    agent creation does NOT appear in the Azure Activity Log and the agent object itself stores
    only a created_at timestamp - no "created by". This script adds an Azure Monitor diagnostic
    setting that streams the account's data-plane log categories (Audit + RequestResponse, and
    optionally Trace) to a Log Analytics workspace. From then on, each agent operation is logged
    with the caller identity, which you can query and resolve to a user (see agent-attribution.kql).

    Note: this only captures operations that happen AFTER the setting is enabled. It cannot
    retroactively attribute agents that already exist.

.PARAMETER AccountResourceId
    Resource ID of the Foundry / Cognitive Services account.

.PARAMETER WorkspaceResourceId
    Resource ID of the Log Analytics workspace to send logs to.

.PARAMETER DiagnosticSettingName
    Name for the diagnostic setting. Default: foundry-audit-attribution.

.PARAMETER IncludeTrace
    Also enable the verbose 'Trace' category (higher volume). Default: off.

.EXAMPLE
    ./Enable-FoundryAgentAuditLogging.ps1 `
        -AccountResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>" `
        -WorkspaceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<law>"

.NOTES
    Requires: Azure CLI (az), signed in (az login) with Monitoring Contributor (or Contributor)
    on the account. Uses the legacy AzureDiagnostics table by default; pass -ResourceSpecific to
    use dedicated tables if your workspace/resource supports them.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AccountResourceId,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceResourceId,

    [string]$DiagnosticSettingName = "foundry-audit-attribution",

    [switch]$IncludeTrace,

    [switch]$ResourceSpecific
)

$ErrorActionPreference = "Stop"

Write-Host "Available diagnostic log categories on the account:" -ForegroundColor Cyan
az monitor diagnostic-settings categories list --resource $AccountResourceId `
    --query "value[?categoryType=='Logs'].name" -o tsv

# Audit  = management-style data-plane operations (create/update/delete)
# RequestResponse = data-plane request/response calls (agent create/list/get surface here as
#                   'Projects_Wildcard_*' with the caller object id in properties_s)
$logs = @(
    @{ category = "Audit"; enabled = $true },
    @{ category = "RequestResponse"; enabled = $true }
)
if ($IncludeTrace) { $logs += @{ category = "Trace"; enabled = $true } }

$logsFile = (New-TemporaryFile).FullName
try {
    $logs | ConvertTo-Json -Depth 10 | Set-Content -Path $logsFile -Encoding utf8

    $createArgs = @(
        "monitor", "diagnostic-settings", "create",
        "--name", $DiagnosticSettingName,
        "--resource", $AccountResourceId,
        "--workspace", $WorkspaceResourceId,
        "--logs", "@$logsFile"
    )
    if ($ResourceSpecific) { $createArgs += @("--export-to-resource-specific", "true") }

    Write-Host "`nCreating diagnostic setting '$DiagnosticSettingName'..." -ForegroundColor Cyan
    az @createArgs -o json | ConvertFrom-Json |
        Select-Object name, @{n = "workspace"; e = { $_.workspaceId } },
        @{n = "categories"; e = { ($_.logs | Where-Object enabled | ForEach-Object category) -join ", " } } |
        Format-List
}
finally {
    Remove-Item $logsFile -ErrorAction SilentlyContinue
}

Write-Host "`nDone. Allow ~5-15 minutes for the first logs to appear in Log Analytics." -ForegroundColor Green
Write-Host "Then run the query in agent-attribution.kql to see agent operations by caller." -ForegroundColor Green
