// =============================================================================
//  bot-service.bicep
//  Per-agent Azure Bot Service + Microsoft Teams channel.
//
//  Replaces the (now removed) Foundry portal "Publish to Teams" one-click button
//  for private-networking projects. Deployed once per published agent by
//  scripts/Publish-AgentToTeams.ps1 (steps 1-2 of the REST publish flow).
//
//  The bot's messaging endpoint is set to the PUBLIC APIM bridge gateway, which
//  forwards inbound Bot Channel Adapter traffic to the private Foundry agent over
//  the VNet. Foundry stays private; only APIM is public.
//
//  Ref: https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure Bot Service resource name (globally unique within the subscription).')
param botName string

@description('Display name shown to users.')
param displayName string

@description('Agent identity principal ID (instance_identity.principal_id from the Foundry Get agent API).')
param msaAppId string

@description('Microsoft Entra tenant ID.')
param tenantId string

@description('Bot messaging endpoint. Point this at the APIM bridge gateway (public) so the Bot Channel Adapter can reach the private Foundry agent through the VNet.')
param endpoint string

@description('Bot Service SKU. F0 (free) is sufficient for a single Teams channel.')
@allowed([
  'F0'
  'S1'
])
param botServiceSku string = 'F0'

@description('Disable public network access to the bot resource itself (management/Direct Line). The Teams channel adapter still reaches the messaging endpoint over the public APIM gateway.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Tags applied to the bot resource.')
param tags object = {}

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  kind: 'azurebot'
  location: 'global'
  tags: tags
  sku: {
    name: botServiceSku
  }
  properties: {
    displayName: displayName
    endpoint: endpoint
    msaAppId: msaAppId
    msaAppTenantId: tenantId
    msaAppType: 'SingleTenant'
    publicNetworkAccess: publicNetworkAccess
  }
}

resource botServiceMsTeamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: botService
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

@description('ARM resource ID of the bot (pass as botServiceArmId when publishing).')
output botServiceArmId string = botService.id

@description('Bot resource name.')
output botName string = botService.name
