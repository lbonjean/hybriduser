@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
param environmentName string = 'dev'

@description('Admin Unit GUID to monitor')
param adminUnitId string

@description('API-driven provisioning endpoint URL')
param provisioningApiEndpoint string

@description('Email addresses for alerts (comma-separated)')
param alertEmailAddresses array

@description('Deploy monitoring alerts (set to false for initial deployment, enable after custom log table exists)')
param deployMonitoring bool = false

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Application: 'HybridUserSync'
  ManagedBy: 'Bicep'
}

// Variables
var resourcePrefix = 'hybriduser-${environmentName}'
var keyVaultName = take('kv-${resourcePrefix}-${uniqueString(resourceGroup().id)}', 24)
var logicAppName = 'logic-${resourcePrefix}'
var logAnalyticsName = 'log-${resourcePrefix}'
var actionGroupName = 'ag-${resourcePrefix}'
var deadLetterStorageName = take('stdl${environmentName}${uniqueString(resourceGroup().id)}', 24)

// Key Vault for storing subscription ID
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Dead Letter Storage Account
resource deadLetterStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: deadLetterStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource deadLetterBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: deadLetterStorage
}

resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'deadletter'
  parent: deadLetterBlobService
  properties: {
    publicAccess: 'None'
  }
}

// Log Analytics Workspace for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
  }
}

// Get Log Analytics workspace keys for API connections
var logAnalyticsWorkspaceId = logAnalytics.properties.customerId
var logAnalyticsWorkspaceKey = logAnalytics.listKeys().primarySharedKey

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: take('HybridUser', 12)
    enabled: true
    emailReceivers: [for (email, i) in alertEmailAddresses: {
      name: 'Email${i}'
      emailAddress: email
      useCommonAlertSchema: true
    }]
  }
}

// Logic App
module logicApp 'logicapp.bicep' = {
  name: 'logicapp-deployment'
  params: {
    location: location
    logicAppName: logicAppName
    keyVaultName: keyVault.name
    adminUnitId: adminUnitId
    provisioningApiEndpoint: provisioningApiEndpoint
    deadLetterStorageAccountName: deadLetterStorage.name
    deadLetterContainerName: deadLetterContainer.name
    logAnalyticsWorkspaceId: logAnalytics.id
    logAnalyticsCustomerId: logAnalyticsWorkspaceId
    logAnalyticsPrimaryKey: logAnalyticsWorkspaceKey
    tags: tags
  }
}

// Role assignments module for Logic App system-assigned identity
module roleAssignments 'role-assignments.bicep' = {
  name: 'role-assignments-deployment'
  params: {
    logicAppPrincipalId: logicApp.outputs.logicAppPrincipalId
    keyVaultId: keyVault.id
    deadLetterStorageId: deadLetterStorage.id
  }
}

// Subscription Renewal Logic App
// Note: The webhook URL needs to be configured manually or via post-deployment script
// because it contains a secret that cannot be referenced directly in Bicep
module subscriptionRenewal 'subscription-renewal.bicep' = {
  name: 'subscription-renewal-deployment'
  params: {
    location: location
    renewalLogicAppName: 'logic-${resourcePrefix}-renewal'
    keyVaultName: keyVault.name
    webhookCallbackUrl: 'https://placeholder.com' // Will be updated by post-deployment script
    logAnalyticsWorkspaceId: logAnalytics.id
    logAnalyticsCustomerId: logAnalyticsWorkspaceId
    logAnalyticsPrimaryKey: logAnalyticsWorkspaceKey
    tags: tags
  }
  dependsOn: [
    roleAssignments
  ]
}

// Monitoring and Alerts (optional - deploy after custom log table exists)
module monitoring 'monitoring.bicep' = if (deployMonitoring) {
  name: 'monitoring-deployment'
  params: {
    location: location
    logicAppName: logicAppName
    logAnalyticsWorkspaceId: logAnalytics.id
    actionGroupId: actionGroup.id
    tags: tags
  }
  dependsOn: [
    logicApp
  ]
}

// Outputs
output logicAppName string = logicAppName
output renewalLogicAppName string = subscriptionRenewal.outputs.renewalLogicAppName
output keyVaultName string = keyVault.name
output logicAppPrincipalId string = logicApp.outputs.logicAppPrincipalId
output renewalLogicAppPrincipalId string = subscriptionRenewal.outputs.renewalLogicAppPrincipalId
output deadLetterStorageAccountName string = deadLetterStorage.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output actionGroupName string = actionGroup.name
