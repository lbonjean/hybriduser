using './main.bicep'

// param location = resourceGroup().location
param namePrefix = 'BVL'
param adminUnitId = '5e061528-c64b-4cf8-8be8-cb5c795cc81a'
param provisioningApiEndpoint = 'https://graph.microsoft.com/v1.0/servicePrincipals/07ce8fae-e8c7-4b6c-8ca5-a7c7093ac4d0/synchronization/jobs/API2AD.bd3c015cc0af4e14a1c19a0673f12540.5df60490-9158-45ee-93e2-2ce824a1e8f1/bulkUpload'
param alertEmailAddresses = []
param deployMonitoring = false
param tags = {
  Application: 'HybridUserSync'
  ManagedBy: 'Bicep'
}

