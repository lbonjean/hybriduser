@description('Location for the Logic App')
param location string

@description('Name of the subscription renewal Logic App')
param renewalLogicAppName string

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

var keyVaultDnsSuffix = environment().suffixes.keyvaultDns
var keyVaultDnsHost = startsWith(keyVaultDnsSuffix, '.') ? substring(keyVaultDnsSuffix, 1) : keyVaultDnsSuffix

// Subscription Renewal Logic App
// Runs every 12 hours to renew the Graph API subscription
resource renewalLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: renewalLogicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
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
            interval: 12
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
            // Get all subscription secrets from Key Vault
            List_subscription_secrets_from_keyvault: {
              type: 'Http'
              inputs: {
                method: 'GET'
                uri: 'https://@{parameters(\'keyVaultName\')}.${keyVaultDnsHost}/secrets?api-version=7.4'
                authentication: {
                  type: 'ManagedServiceIdentity'
                  audience: 'https://${keyVaultDnsHost}'
                }
              }
              runAfter: {}
            }
            Parse_keyvault_secrets_response: {
              type: 'ParseJson'
              inputs: {
                content: '@body(\'List_subscription_secrets_from_keyvault\')'
                schema: {
                  type: 'object'
                  properties: {
                    value: {
                      type: 'array'
                      items: {
                        type: 'object'
                        properties: {
                          id: {
                            type: 'string'
                          }
                        }
                        required: [
                          'id'
                        ]
                      }
                    }
                  }
                  required: [
                    'value'
                  ]
                }
              }
              runAfter: {
                List_subscription_secrets_from_keyvault: ['Succeeded']
              }
            }
            Validate_secret_count: {
              type: 'If'
              expression: {
                greater: [
                  '@length(body(\'Parse_keyvault_secrets_response\')?[\'value\'])'
                  1
                ]
              }
              runAfter: {
                Parse_keyvault_secrets_response: ['Succeeded']
              }
              actions: {
                Log_multiple_secrets_error: {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    body: '@{json(concat(\'[{"EventType":"SubscriptionRenewalFailure","ErrorDetails":"More than one Key Vault subscription secret found","SecretCount":"\',string(length(body(\'Parse_keyvault_secrets_response\')?[\'value\'])),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                    headers: {
                      'Log-Type': 'HybridUserSync'
                    }
                    path: '/api/logs'
                  }
                  runAfter: {}
                }
                Fail_multiple_secrets_found: {
                  type: 'Terminate'
                  inputs: {
                    runStatus: 'Failed'
                    code: 'MultipleSubscriptionSecretsFound'
                    message: 'Expected exactly zero or one Key Vault secret for subscription ID, but found more than one.'
                  }
                  runAfter: {
                    Log_multiple_secrets_error: ['Succeeded']
                  }
                }
              }
              else: {
                actions: {
                  // Check if exactly one subscription secret exists
                  Check_if_subscription_exists: {
                    type: 'If'
                    expression: {
                      equals: [
                        '@length(body(\'Parse_keyvault_secrets_response\')?[\'value\'])'
                        1
                      ]
                    }
                    runAfter: {}
                    actions: {
                      // Extract secret name (GUID) from secret ID URL
                      Set_subscription_id: {
                        type: 'SetVariable'
                        inputs: {
                          name: 'subscriptionId'
                          value: '@{first(split(last(split(first(body(\'Parse_keyvault_secrets_response\')?[\'value\'])?[\'id\'],\'/secrets/\')),\'/\'))}'
                        }
                        runAfter: {}
                      }
                      // Calculate new expiration (12 hours)
                      Calculate_expiration: {
                        type: 'Compose'
                        inputs: '@addMinutes(utcNow(), 730)'
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
                      // If renew fails because subscription is invalid, remove secret and create a new subscription
                      Handle_failed_renewal: {
                        type: 'If'
                        expression: {
                          or: [
                            {
                              equals: [
                                '@outputs(\'Renew_subscription\')?[\'statusCode\']'
                                404
                              ]
                            }
                            {
                              equals: [
                                '@outputs(\'Renew_subscription\')?[\'statusCode\']'
                                410
                              ]
                            }
                          ]
                        }
                        runAfter: {
                          Renew_subscription: ['Failed']
                        }
                        actions: {
                          Delete_invalid_subscription_secret: {
                            type: 'Http'
                            inputs: {
                              method: 'DELETE'
                              uri: 'https://@{parameters(\'keyVaultName\')}.${keyVaultDnsHost}/secrets/@{variables(\'subscriptionId\')}?api-version=7.4'
                              authentication: {
                                type: 'ManagedServiceIdentity'
                                audience: 'https://${keyVaultDnsHost}'
                              }
                            }
                            runAfter: {}
                          }
                          Log_creating_new_subscription_after_invalid: {
                            type: 'ApiConnection'
                            inputs: {
                              host: {
                                connection: {
                                  name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                }
                              }
                              method: 'post'
                              body: '@{json(concat(\'[{"EventType":"CreatingNewSubscription","Reason":"InvalidExistingSubscription","PreviousSubscriptionId":"\',variables(\'subscriptionId\'),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                              headers: {
                                'Log-Type': 'HybridUserSync'
                              }
                              path: '/api/logs'
                            }
                            runAfter: {
                              Delete_invalid_subscription_secret: ['Succeeded', 'Failed']
                            }
                          }
                          Calculate_new_expiration_after_invalid: {
                            type: 'Compose'
                            inputs: '@addMinutes(utcNow(), 730)'
                            runAfter: {
                              Log_creating_new_subscription_after_invalid: ['Succeeded']
                            }
                          }
                          Create_subscription_after_invalid: {
                            type: 'Http'
                            inputs: {
                              method: 'POST'
                              uri: 'https://graph.microsoft.com/v1.0/subscriptions'
                              authentication: {
                                type: 'ManagedServiceIdentity'
                                audience: 'https://graph.microsoft.com'
                              }
                              headers: {
                                'Content-Type': 'application/json'
                              }
                              body: {
                                changeType: 'updated'
                                notificationUrl: '@{parameters(\'webhookCallbackUrl\')}'
                                resource: '/users'
                                expirationDateTime: '@{outputs(\'Calculate_new_expiration_after_invalid\')}'
                                clientState: 'HybridUserSync'
                              }
                            }
                            runAfter: {
                              Calculate_new_expiration_after_invalid: ['Succeeded']
                            }
                          }
                          Parse_create_response_after_invalid: {
                            type: 'ParseJson'
                            inputs: {
                              content: '@body(\'Create_subscription_after_invalid\')'
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
                              Create_subscription_after_invalid: ['Succeeded']
                            }
                          }
                          Store_subscription_id_after_invalid: {
                            type: 'Http'
                            inputs: {
                              method: 'PUT'
                              uri: 'https://@{parameters(\'keyVaultName\')}.${keyVaultDnsHost}/secrets/@{body(\'Parse_create_response_after_invalid\')?[\'id\']}?api-version=7.4'
                              authentication: {
                                type: 'ManagedServiceIdentity'
                                audience: 'https://${keyVaultDnsHost}'
                              }
                              headers: {
                                'Content-Type': 'application/json'
                              }
                              body: {
                                value: '@{body(\'Parse_create_response_after_invalid\')?[\'id\']}'
                              }
                            }
                            runAfter: {
                              Parse_create_response_after_invalid: ['Succeeded']
                            }
                          }
                          Log_creation_success_after_invalid: {
                            type: 'ApiConnection'
                            inputs: {
                              host: {
                                connection: {
                                  name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                }
                              }
                              method: 'post'
                              body: '@{json(concat(\'[{"EventType":"SubscriptionRenewalSuccess","SubscriptionId":"\',body(\'Parse_create_response_after_invalid\')?[\'id\'],\'","NewExpiration":"\',outputs(\'Calculate_new_expiration_after_invalid\'),\'","Action":"RecreatedAfterInvalid","Timestamp":"\',utcNow(),\'"}]\'))}'
                              headers: {
                                'Log-Type': 'HybridUserSync'
                              }
                              path: '/api/logs'
                            }
                            runAfter: {
                              Store_subscription_id_after_invalid: ['Succeeded']
                            }
                          }
                        }
                        else: {
                          actions: {
                            Fail_nonrecoverable_renewal_error: {
                              type: 'Terminate'
                              inputs: {
                                runStatus: 'Failed'
                                code: 'SubscriptionRenewalFailed'
                                message: 'Renewal failed with a non-recoverable error and was not recreated.'
                              }
                              runAfter: {}
                            }
                          }
                        }
                      }
                    }
                    else: {
                      actions: {
                        // Create new subscription when no existing secret is found
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
                          inputs: '@addMinutes(utcNow(), 730)'
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
                        // Store subscription ID in Key Vault using the GUID as secret name
                        Store_subscription_id: {
                          type: 'Http'
                          inputs: {
                            method: 'PUT'
                            uri: 'https://@{parameters(\'keyVaultName\')}.${keyVaultDnsHost}/secrets/@{body(\'Parse_create_response\')?[\'id\']}?api-version=7.4'
                            authentication: {
                              type: 'ManagedServiceIdentity'
                              audience: 'https://${keyVaultDnsHost}'
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
output renewalLogicAppPrincipalId string = renewalLogicApp.identity.principalId
