@description('Location for monitoring resources')
param location string

@description('Logic App name to monitor')
param logicAppName string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Action Group ID for alerts')
param actionGroupId string

@description('Tags')
param tags object

// Alert: Logic App Run Failures
resource alertRunFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-failures'
  location: location
  tags: tags
  properties: {
    displayName: 'Logic App Run Failures'
    description: 'Alert when Logic App runs fail'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.LOGIC"\n| where resource_workflowName_s == "${logicAppName}"\n| where status_s == "Failed"\n| summarize Count = count() by bin(TimeGenerated, 5m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: Processing Errors (Custom Logs)
resource alertProcessingErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-processing-errors'
  location: location
  tags: tags
  properties: {
    displayName: 'User Processing Errors'
    description: 'Alert when user processing encounters errors'
    severity: 2
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "ProcessingError"\n| summarize Count = count() by bin(TimeGenerated, 5m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: Successful Provisioning (Info)
resource alertProvisioningSuccess 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-provisioning-success'
  location: location
  tags: tags
  properties: {
    displayName: 'Successful User Provisioning'
    description: 'Notification when users are successfully provisioned to AD DS'
    severity: 3
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT15M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "ProvisioningSuccess"\n| summarize Count = count() by bin(TimeGenerated, 15m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: Subscription Renewal Success
resource alertSubscriptionRenewalSuccess 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-renewal-success'
  location: location
  tags: tags
  properties: {
    displayName: 'Subscription Renewal Success'
    description: 'Heartbeat: Subscription successfully renewed'
    severity: 3
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT15M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "SubscriptionRenewalSuccess"\n| summarize Count = count() by bin(TimeGenerated, 15m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: Subscription Renewal Failure
resource alertSubscriptionRenewalFailure 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-renewal-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'Subscription Renewal Failure'
    description: 'Alert when subscription renewal fails'
    severity: 1
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "SubscriptionRenewalFailure"\n| summarize Count = count() by bin(TimeGenerated, 5m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: No Subscription Renewal in 60 hours (Heartbeat)
resource alertNoRenewalHeartbeat 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-no-renewal-heartbeat'
  location: location
  tags: tags
  properties: {
    displayName: 'No Subscription Renewal (Heartbeat)'
    description: 'Alert when no subscription renewal has occurred in the last 48 hours'
    severity: 1
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT1H'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT48H'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "SubscriptionRenewalSuccess"\n| summarize Count = count()'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'LessThanOrEqual'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

// Alert: Source of Authority Success
resource alertSourceOfAuthoritySuccess 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-${logicAppName}-soa-success'
  location: location
  tags: tags
  properties: {
    displayName: 'Source of Authority Change Success'
    description: 'Notification when source of authority is successfully changed to Entra'
    severity: 3
    enabled: false  // Enable after first logs are written
    evaluationFrequency: 'PT15M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'HybridUserSync_CL\n| where EventType_s == "SourceOfAuthoritySuccess"\n| summarize Count = count() by bin(TimeGenerated, 15m)'
          timeAggregation: 'Total'
          metricMeasureColumn: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
    autoMitigate: true
  }
}

output alertIds array = [
  alertRunFailures.id
  alertProcessingErrors.id
  alertProvisioningSuccess.id
  alertSubscriptionRenewalSuccess.id
  alertSubscriptionRenewalFailure.id
  alertNoRenewalHeartbeat.id
  alertSourceOfAuthoritySuccess.id
]
