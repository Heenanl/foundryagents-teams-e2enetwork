// =============================================================================
//  main.bicep
//  Orchestrates the private-Foundry -> Teams APIM bridge:
//    network (subnet+NSG) -> APIM Std v2 (VNet outbound) -> API+operation -> policy
//
//  Deployed into the EXISTING resource group that holds the private Foundry
//  deployment (so it can reference the existing VNet).
// =============================================================================

targetScope = 'resourceGroup'

// ── Parameters ────────────────────────────────────────────────────────────────
@description('Location for all bridge resources (match the VNet/Foundry region).')
param location string

@description('Existing VNet hosting the private Foundry deployment.')
param vnetName string

@description('Dedicated subnet to create for APIM VNet integration.')
param apimSubnetName string

@description('Address prefix (/27 or larger) for the APIM subnet. Must be free in the VNet.')
param apimSubnetPrefix string

@description('NSG to create and associate with the APIM subnet.')
param nsgName string

@description('APIM service name (globally unique).')
param apimName string

@description('APIM publisher organization name.')
param apimPublisherName string

@description('APIM publisher contact email.')
param apimPublisherEmail string

@description('APIM v2 capacity (scale units).')
param apimCapacity int = 1

@description('Bridge API identifier.')
param apiId string = 'foundry-activity'

@description('Bridge API path.')
param apiPath string = 'foundry'

@description('Private Foundry data-plane host, e.g. https://<account>.services.ai.azure.com')
param foundryHost string

@description('Fallback Foundry activity-protocol API version (used only if a bot endpoint omits it).')
param foundryApiVersion string = '2025-11-15-preview'

@description('Tags applied to all created resources.')
param tags object = {}

// ── 1. Network: subnet + NSG ──────────────────────────────────────────────────
module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
    vnetName: vnetName
    apimSubnetName: apimSubnetName
    apimSubnetPrefix: apimSubnetPrefix
    nsgName: nsgName
    tags: tags
  }
}

// ── 2. APIM Standard v2 with VNet outbound integration ────────────────────────
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  params: {
    apimName: apimName
    location: location
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    subnetId: network.outputs.apimSubnetId
    skuCapacity: apimCapacity
    tags: tags
  }
}

// ── 3. Named values (foundry-api-version) ─────────────────────────────────────
module apimConfig 'modules/apim-config.bicep' = {
  name: 'deploy-apim-config'
  params: {
    apimServiceName: apim.outputs.apimName
    namedValues: [
      {
        name: 'foundry-api-version'
        displayName: 'foundry-api-version'
        value: foundryApiVersion
        secret: false
      }
    ]
  }
}

// ── 4. Bridge API + templated all-agents operation ────────────────────────────
module apimApi 'modules/apim-api.bicep' = {
  name: 'deploy-apim-api'
  params: {
    apimServiceName: apim.outputs.apimName
    apiId: apiId
    apiPath: apiPath
    foundryHost: foundryHost
  }
}

// ── 5. Attach the bridge policy (depends on named value + API) ────────────────
module apimPolicies 'modules/apim-policies.bicep' = {
  name: 'deploy-apim-policies'
  params: {
    apimServiceName: apim.outputs.apimName
    apiId: apimApi.outputs.apiId
    policyXml: loadTextContent('../apim-policies/foundry-activity-policy.xml')
  }
  dependsOn: [
    apimConfig
  ]
}

// ── Outputs ───────────────────────────────────────────────────────────────────
@description('APIM public gateway URL.')
output apimGatewayUrl string = apim.outputs.gatewayUrl

@description('APIM service name.')
output apimName string = apim.outputs.apimName

@description('Bridge API path.')
output apiPath string = apiPath

@description('Templated endpoint pattern bots should point at (per project/agent).')
output endpointPattern string = '${apim.outputs.gatewayUrl}/${apiPath}/api/projects/{project}/agents/{agent}/endpoint/protocols/activityprotocol?api-version=${foundryApiVersion}'
