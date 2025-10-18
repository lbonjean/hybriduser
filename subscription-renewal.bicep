@description('Location for the Logic App')
param location string

@description('Name of the subscription renewal Logic App')
param renewalLogicAppName string

@description('Managed Identity Resource ID')
param managedIdentityId string

@description('Key Vault name')
param keyVaultName string

@description('Main Logic App callback URL')
param webhookCallbackUrl string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Workspace Customer ID (GUID)')
param logAnalyticsCustomerId string

@description('Log Analytics Workspace Primary Shared Key')
@secure()
param logAnalyticsPrimaryKey string

@description('Tags')
param tags object

// Subscription Renewal Logic App
// Runs every 36 hours to renew the Graph API subscription
resource renewalLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: renewalLogicAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        keyVaultName: {
          defaultValue: keyVaultName
          type: 'String'
        }
        webhookCallbackUrl: {
          defaultValue: webhookCallbackUrl
          type: 'String'
        }
      }
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Hour'
            interval: 35
          }
        }
      }
      actions: {
        // Initialize variable for subscription ID at top level
        Initialize_subscription_id: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'subscriptionId'
                type: 'string'
                value: ''
              }
            ]
          }
          runAfter: {}
        }
        // Scope for error handling
        Renewal_scope: {
          type: 'Scope'
          actions: {
            // Try to get existing subscription ID from Key Vault
            Get_subscription_id_from_keyvault: {
              type: 'Http'
              inputs: {
                method: 'GET'
                uri: 'https://@{parameters(\'keyVaultName\')}.vault.azure.net/secrets/graph-subscription-id?api-version=7.4'
                authentication: {
                  type: 'ManagedServiceIdentity'
                  identity: managedIdentityId
                  audience: 'https://vault.azure.net'
                }
              }
              runAfter: {}
            }
            Parse_keyvault_response: {
              type: 'ParseJson'
              inputs: {
                content: '@body(\'Get_subscription_id_from_keyvault\')'
                schema: {
                  type: 'object'
                  properties: {
                    value: {
                      type: 'string'
                    }
                  }
                }
              }
              runAfter: {
                Get_subscription_id_from_keyvault: ['Succeeded']
              }
            }
            // Check if we have a subscription ID
            Check_if_subscription_exists: {
              type: 'If'
              expression: {
                and: [
                  {
                    equals: [
                      '@actions(\'Get_subscription_id_from_keyvault\').status'
                      'Succeeded'
                    ]
                  }
                ]
              }
              runAfter: {
                Parse_keyvault_response: ['Succeeded', 'Skipped']
              }
              actions: {
                // Try to renew existing subscription
                Set_subscription_id: {
                  type: 'SetVariable'
                  inputs: {
                    name: 'subscriptionId'
                    value: '@body(\'Parse_keyvault_response\')?[\'value\']'
                  }
                  runAfter: {}
                }
                // Calculate new expiration (3 days from now)
                Calculate_expiration: {
                  type: 'Compose'
                  inputs: '@addMinutes(utcNow(), 4200)'
                  runAfter: {
                    Set_subscription_id: ['Succeeded']
                  }
                }
                // Renew subscription
                Renew_subscription: {
                  type: 'Http'
                  inputs: {
                    method: 'PATCH'
                    uri: 'https://graph.microsoft.com/v1.0/subscriptions/@{variables(\'subscriptionId\')}'
                    authentication: {
                      type: 'ManagedServiceIdentity'
                      identity: managedIdentityId
                      audience: 'https://graph.microsoft.com'
                    }
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      expirationDateTime: '@{outputs(\'Calculate_expiration\')}'
                    }
                  }
                  runAfter: {
                    Calculate_expiration: ['Succeeded']
                  }
                }
                // Log successful renewal
                Log_renewal_success: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '@{json(concat(\'[{"EventType":"SubscriptionRenewalSuccess","SubscriptionId":"\',variables(\'subscriptionId\'),\'","NewExpiration":"\',outputs(\'Calculate_expiration\'),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                    headers: {
                      'Log-Type': 'HybridUserSync'
                    }
                    path: '/api/logs'
                  }
                  runAfter: {
                    Renew_subscription: ['Succeeded']
                  }
                }
              }
              else: {
                actions: {
                  // Create new subscription
                  Log_creating_new_subscription: {
                    type: 'ApiConnection'
                    inputs: {
                      host: {
                        connection: {
                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                        }
                      }
                      method: 'post'
                      body: '@{json(concat(\'[{"EventType":"CreatingNewSubscription","Timestamp":"\',utcNow(),\'"}]\'))}'
                      headers: {
                        'Log-Type': 'HybridUserSync'
                      }
                      path: '/api/logs'
                    }
                    runAfter: {}
                  }
                  Calculate_new_expiration: {
                    type: 'Compose'
                    inputs: '@addMinutes(utcNow(), 4200)'
                    runAfter: {
                      Log_creating_new_subscription: ['Succeeded']
                    }
                  }
                  // Create subscription for user updates
                  Create_subscription: {
                    type: 'Http'
                    inputs: {
                      method: 'POST'
                      uri: 'https://graph.microsoft.com/v1.0/subscriptions'
                      authentication: {
                        type: 'ManagedServiceIdentity'
                        identity: managedIdentityId
                        audience: 'https://graph.microsoft.com'
                      }
                      headers: {
                        'Content-Type': 'application/json'
                      }
                      body: {
                        changeType: 'updated'
                        notificationUrl: '@{parameters(\'webhookCallbackUrl\')}'
                        resource: '/users'
                        expirationDateTime: '@{outputs(\'Calculate_new_expiration\')}'
                        clientState: 'HybridUserSync'
                      }
                    }
                    runAfter: {
                      Calculate_new_expiration: ['Succeeded']
                    }
                  }
                  Parse_create_response: {
                    type: 'ParseJson'
                    inputs: {
                      content: '@body(\'Create_subscription\')'
                      schema: {
                        type: 'object'
                        properties: {
                          id: {
                            type: 'string'
                          }
                          resource: {
                            type: 'string'
                          }
                          changeType: {
                            type: 'string'
                          }
                          expirationDateTime: {
                            type: 'string'
                          }
                        }
                      }
                    }
                    runAfter: {
                      Create_subscription: ['Succeeded']
                    }
                  }
                  // Store subscription ID in Key Vault
                  Store_subscription_id: {
                    type: 'Http'
                    inputs: {
                      method: 'PUT'
                      uri: 'https://@{parameters(\'keyVaultName\')}.vault.azure.net/secrets/graph-subscription-id?api-version=7.4'
                      authentication: {
                        type: 'ManagedServiceIdentity'
                        identity: managedIdentityId
                        audience: 'https://vault.azure.net'
                      }
                      headers: {
                        'Content-Type': 'application/json'
                      }
                      body: {
                        value: '@{body(\'Parse_create_response\')?[\'id\']}'
                      }
                    }
                    runAfter: {
                      Parse_create_response: ['Succeeded']
                    }
                  }
                  // Log successful creation
                  Log_creation_success: {
                    type: 'ApiConnection'
                    inputs: {
                      host: {
                        connection: {
                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                        }
                      }
                      method: 'post'
                      body: '@{json(concat(\'[{"EventType":"SubscriptionRenewalSuccess","SubscriptionId":"\',body(\'Parse_create_response\')?[\'id\'],\'","NewExpiration":"\',outputs(\'Calculate_new_expiration\'),\'","Action":"Created","Timestamp":"\',utcNow(),\'"}]\'))}'
                      headers: {
                        'Log-Type': 'HybridUserSync'
                      }
                      path: '/api/logs'
                    }
                    runAfter: {
                      Store_subscription_id: ['Succeeded']
                    }
                  }
                }
              }
            }
          }
          runAfter: {
            Initialize_subscription_id: ['Succeeded']
          }
        }
        // Error handling
        Handle_renewal_error: {
          type: 'Scope'
          actions: {
            Log_renewal_failure: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                  }
                }
                method: 'post'
                body: '@{json(concat(\'[{"EventType":"SubscriptionRenewalFailure","ErrorDetails":"\',base64(string(result(\'Renewal_scope\'))),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                headers: {
                  'Log-Type': 'HybridUserSync'
                }
                path: '/api/logs'
              }
              runAfter: {}
            }
          }
          runAfter: {
            Renewal_scope: ['Failed', 'Skipped', 'TimedOut']
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureloganalyticsdatacollector: {
            connectionId: azureLogAnalyticsConnection.id
            connectionName: azureLogAnalyticsConnection.name
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
          }
        }
      }
    }
  }
}

// API Connection for Azure Log Analytics
resource azureLogAnalyticsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureloganalyticsdatacollector-${renewalLogicAppName}'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Log Analytics Connection (Renewal)'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
    parameterValues: {
      username: logAnalyticsCustomerId
      password: logAnalyticsPrimaryKey
    }
  }
}

// Diagnostic settings
resource renewalLogicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: renewalLogicApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output renewalLogicAppId string = renewalLogicApp.id
output renewalLogicAppName string = renewalLogicApp.name
