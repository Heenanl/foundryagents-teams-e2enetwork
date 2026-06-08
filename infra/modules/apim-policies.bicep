// =============================================================================
//  apim-policies.bicep
//  Attaches the API-level policy (loaded from apim-policies/ XML) to the bridge
//  API. The policy injects the required api-version (fallback only) and strips
//  the APIM subscription key.
// =============================================================================

@description('APIM service name.')
param apimServiceName string

@description('API identifier the policy is applied to.')
param apiId string

@description('Raw XML policy content.')
param policyXml string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = {
  parent: apim
  name: apiId
}

resource policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: policyXml
  }
}
