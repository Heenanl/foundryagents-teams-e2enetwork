// =============================================================================
//  apim-api.bicep
//  The bridge API and ONE templated operation that matches EVERY Foundry agent
//  (any project, any agent name). Configure once; never changes per new agent.
// =============================================================================

@description('APIM service name.')
param apimServiceName string

@description('API identifier.')
param apiId string

@description('API path (gateway URL becomes https://<apim>.azure-api.net/<apiPath>/...).')
param apiPath string

@description('Private Foundry data-plane host, e.g. https://<account>.services.ai.azure.com')
param foundryHost string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiId
  properties: {
    displayName: 'Foundry Bot Activity Bridge'
    path: apiPath
    serviceUrl: foundryHost
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

// {project} and {agent} are wildcards -> matches every agent's activity endpoint.
resource operation 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: api
  name: 'activity-all'
  properties: {
    displayName: 'Agent Activity (all projects/agents)'
    method: 'POST'
    urlTemplate: '/api/projects/{project}/agents/{agent}/endpoint/protocols/activityprotocol'
    templateParameters: [
      {
        name: 'project'
        required: true
        type: 'string'
      }
      {
        name: 'agent'
        required: true
        type: 'string'
      }
    ]
  }
}

@description('The API identifier (for downstream policy attachment).')
output apiId string = api.name
