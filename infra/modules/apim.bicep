// =============================================================================
//  apim.bicep
//  Azure API Management Standard v2 instance with public gateway + VNet outbound
//  integration. The gateway is reachable by Azure Bot Service (public); outbound
//  integration lets it reach the private Foundry endpoint over the VNet.
// =============================================================================

@description('APIM service name (globally unique).')
param apimName string

@description('Location for the APIM instance.')
param location string

@description('APIM publisher organization name.')
param publisherName string

@description('APIM publisher contact email.')
param publisherEmail string

@description('Resource ID of the delegated subnet for VNet outbound integration.')
param subnetId string

@description('APIM v2 capacity (scale units).')
param skuCapacity int = 1

@description('Public network access to the APIM gateway. Must stay Enabled so Azure Bot Service can reach it.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Developer portal status. Disabled by default (not needed for the bridge).')
@allowed([
  'Enabled'
  'Disabled'
])
param developerPortalStatus string = 'Disabled'

@description('Legacy portal status. Disabled by default.')
@allowed([
  'Enabled'
  'Disabled'
])
param legacyPortalStatus string = 'Disabled'

@description('NAT gateway state for outbound connectivity (Standard v2).')
@allowed([
  'Enabled'
  'Disabled'
])
param natGatewayState string = 'Enabled'

@description('Tags to apply to the APIM instance.')
param tags object = {}

// Security hardening: disable weak TLS/SSL protocols on gateway and backend.
var secureCustomProperties = {
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
  'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'StandardV2'
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: subnetId
    }
    publicNetworkAccess: publicNetworkAccess
    developerPortalStatus: developerPortalStatus
    legacyPortalStatus: legacyPortalStatus
    natGatewayState: natGatewayState
    customProperties: secureCustomProperties
  }
}

@description('APIM service name.')
output apimName string = apim.name

@description('APIM public gateway URL.')
output gatewayUrl string = apim.properties.gatewayUrl

@description('APIM system-assigned managed identity principal ID.')
output principalId string = apim.identity.principalId
