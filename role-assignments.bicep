@description('Logic App Principal ID (System-Assigned Identity)')
param logicAppPrincipalId string

@description('Key Vault Resource ID')
param keyVaultId string

@description('Dead Letter Storage Account Resource ID')
param deadLetterStorageId string

// Grant Key Vault Secrets Officer role to Logic App System-Assigned Identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, logicAppPrincipalId, 'Key Vault Secrets Officer')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: logicAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Storage Blob Data Contributor to Logic App System-Assigned Identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deadLetterStorageId, logicAppPrincipalId, 'Storage Blob Data Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
