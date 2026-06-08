using 'main.bicep'

// ── TEST parameter set: a clean SECOND APIM for end-to-end validation ─────────
// Deploys alongside the production bridge without touching it. Use with:
//   ./deploy.ps1 -ParametersFile infra/main.test.parameters.bicepparam -SkipOnboard

// ── Region / existing private Foundry VNet ────────────────────────────────────
param location = 'swedencentral'
param vnetName = 'agent-vnet-test'

// ── APIM subnet (a SECOND free /27 block; each APIM needs its own subnet) ──────
param apimSubnetName = 'snet-apim-bridge2'
param apimSubnetPrefix = '192.168.3.32/27'
param nsgName = 'nsg-apim-bridge2'

// ── Second APIM instance ──────────────────────────────────────────────────────
param apimName = 'apim-foundry-bridge2'
param apimPublisherName = 'Platform Team'
param apimPublisherEmail = 'platform email' // CHANGE THIS
param apimCapacity = 1

// ── Bridge API ────────────────────────────────────────────────────────────────
param apiId = 'foundry-activity'
param apiPath = 'foundry'

// ── Private Foundry backend (same as production) ──────────────────────────────
param foundryHost = 'https://<foundry-resource>.services.ai.azure.com'
param foundryApiVersion = '2025-11-15-preview'

param tags = {
  project: 'foundry-teams-bridge'
  environment: 'test'
  managedBy: 'Deploy-FoundryTeamsBridge'
}
