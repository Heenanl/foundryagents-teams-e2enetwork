// =============================================================================
//  network.bicep
//  Creates a dedicated subnet (delegated to Microsoft.Web/serverFarms) and an
//  NSG for APIM Standard v2 VNet outbound integration, inside the EXISTING VNet
//  that hosts the private Foundry deployment.
// =============================================================================

@description('Location for the NSG (same region as the VNet/APIM).')
param location string

@description('Name of the existing VNet hosting the private Foundry deployment.')
param vnetName string

@description('Name of the dedicated subnet to create for APIM VNet integration.')
param apimSubnetName string

@description('Address prefix (/27 or larger) for the APIM subnet. Must be free in the VNet.')
param apimSubnetPrefix string

@description('Name of the NSG to create and associate with the APIM subnet.')
param nsgName string

@description('Tags to apply to created resources.')
param tags object = {}

// Existing VNet (from the private Foundry deployment)
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

// NSG with the outbound rules APIM v2 VNet integration requires
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-KeyVault-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Dedicated, delegated subnet for APIM outbound integration.
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: apimSubnetName
  properties: {
    addressPrefix: apimSubnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
    delegations: [
      {
        name: 'apim-serverfarms-delegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

@description('Resource ID of the delegated APIM subnet.')
output apimSubnetId string = apimSubnet.id

@description('Resource ID of the created NSG.')
output nsgId string = nsg.id
