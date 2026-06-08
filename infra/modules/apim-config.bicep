// =============================================================================
//  apim-config.bicep
//  Creates APIM named values. Used here for 'foundry-api-version', referenced by
//  the bridge policy as {{foundry-api-version}} so the activity-protocol API
//  version can be updated without editing policy XML.
// =============================================================================

@description('APIM service name.')
param apimServiceName string

@description('Named values to create. Each item: { name, displayName, value, secret }.')
param namedValues array

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource nv 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [
  for item in namedValues: {
    parent: apim
    name: item.name
    properties: {
      displayName: item.displayName
      value: item.value
      secret: item.?secret ?? false
    }
  }
]

@description('Names of the created named values.')
output namedValueNames array = [for item in namedValues: item.name]
