using 'main.bicep'

// ── Region / existing private Foundry VNet ────────────────────────────────────
param location = 'swedencentral'
param vnetName = 'agent-vnet-test'

// ── APIM subnet (must be a FREE /27+ block in the VNet address space) ──────────
param apimSubnetName = 'snet-apim-bridge'
param apimSubnetPrefix = '192.168.3.0/27'
param nsgName = 'nsg-apim-bridge'

// ── APIM instance ─────────────────────────────────────────────────────────────
param apimName = 'apim-foundry-bridge'
param apimPublisherName = 'Platform Team'
param apimPublisherEmail = 'platform email' // CHANGE THIS
param apimCapacity = 1

// ── Bridge API ────────────────────────────────────────────────────────────────
param apiId = 'foundry-activity'
param apiPath = 'foundry'

// ── Private Foundry backend ───────────────────────────────────────────────────
param foundryHost = 'https://<foundry-resource>.services.ai.azure.com'
param foundryApiVersion = '2025-11-15-preview'

param tags = {
  project: 'foundry-teams-bridge'
  managedBy: 'Deploy-FoundryTeamsBridge'
}
