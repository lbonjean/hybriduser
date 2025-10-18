@description('Location for the Logic App')
param location string

@description('Name of the Logic App')
param logicAppName string

@description('Key Vault name')
param keyVaultName string

@description('Admin Unit GUID')
param adminUnitId string

@description('Provisioning API endpoint')
param provisioningApiEndpoint string

@description('Dead Letter Storage Account name')
param deadLetterStorageAccountName string

@description('Dead Letter Container name')
param deadLetterContainerName string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

@description('Log Analytics Workspace Customer ID (GUID)')
param logAnalyticsCustomerId string

@description('Log Analytics Workspace Primary Shared Key')
@secure()
param logAnalyticsPrimaryKey string

@description('Tags')
param tags object

// Logic App with workflow definition
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
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
        adminUnitId: {
          defaultValue: adminUnitId
          type: 'String'
        }
        provisioningApiEndpoint: {
          defaultValue: provisioningApiEndpoint
          type: 'String'
        }
        deadLetterStorageAccount: {
          defaultValue: deadLetterStorageAccountName
          type: 'String'
        }
        deadLetterContainer: {
          defaultValue: deadLetterContainerName
          type: 'String'
        }
        disableSourceOfAuthorityUpdate: {
          defaultValue: false
          type: 'Bool'
        }
        allowedAdminUnitNames: {
          defaultValue: []
          type: 'Array'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                value: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      subscriptionId: {
                        type: 'string'
                      }
                      clientState: {
                        type: 'string'
                      }
                      expirationDateTime: {
                        type: 'string'
                      }
                      resource: {
                        type: 'string'
                      }
                      tenantId: {
                        type: 'string'
                      }
                      resourceData: {
                        type: 'object'
                      }
                    }
                  }
                }
                validationToken: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        // Initialize variables at top level
        Initialize_error_variable: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'hasError'
                type: 'boolean'
                value: false
              }
            ]
          }
          runAfter: {}
        }
        Initialize_error_message: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'errorMessage'
                type: 'string'
                value: ''
              }
            ]
          }
          runAfter: {
            Initialize_error_variable: ['Succeeded']
          }
        }
        Initialize_user_id: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'userId'
                type: 'string'
                value: ''
              }
            ]
          }
          runAfter: {
            Initialize_error_message: ['Succeeded']
          }
        }
        // Handle validation request from Graph API
        Check_if_validation_request: {
          type: 'If'
          expression: {
            and: [
              {
                not: {
                  equals: [
                    '@trigger()[\'outputs\']?[\'queries\']?[\'validationToken\']'
                    null
                  ]
                }
              }
            ]
          }
          actions: {
            Return_validation_token: {
              type: 'Response'
              kind: 'Http'
              inputs: {
                statusCode: 200
                headers: {
                  'Content-Type': 'text/plain'
                }
                body: '@{trigger()[\'outputs\']?[\'queries\']?[\'validationToken\']}'
              }
            }
          }
          else: {
            actions: {
              // Immediately return 202 Accepted to Graph API
              Return_accepted_response: {
                type: 'Response'
                kind: 'Http'
                inputs: {
                  statusCode: 202
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    status: 'accepted'
                    message: 'Change notifications will be processed asynchronously'
                  }
                }
                runAfter: {}
              }
              // Process each notification
              For_each_notification: {
                type: 'Foreach'
                foreach: '@triggerBody()?[\'value\']'
                actions: {
                  // Set user ID from resource path
                  Set_user_id: {
                    type: 'SetVariable'
                    inputs: {
                      name: 'userId'
                      value: '@{last(split(items(\'For_each_notification\')?[\'resource\'], \'/\'))}'
                    }
                    runAfter: {}
                  }
                  // Scope for error handling
                  Process_user_scope: {
                    type: 'Scope'
                    actions: {
                      // Get user details from Graph API
                      Get_user_details: {
                        type: 'Http'
                        inputs: {
                          method: 'GET'
                          uri: 'https://graph.microsoft.com/beta/users/@{variables(\'userId\')}?$select=id,userPrincipalName,onPremisesImmutableId,onPremisesSyncEnabled,displayName,givenName,surname,mail,employeeId,department,companyName,jobTitle,mobilePhone,businessPhones,onPremisesSyncBehavior'
                          authentication: {
                            type: 'ManagedServiceIdentity'
                            audience: 'https://graph.microsoft.com'
                          }
                        }
                        runAfter: {}
                      }
                      // Parse user response
                      Parse_user_details: {
                        type: 'ParseJson'
                        inputs: {
                          content: '@body(\'Get_user_details\')'
                          schema: {
                            type: 'object'
                            properties: {
                              id: { type: 'string' }
                              userPrincipalName: { type: 'string' }
                              displayName: { type: 'string' }
                              onPremisesImmutableId: { type: ['string', 'null'] }
                              onPremisesSyncEnabled: { type: ['boolean', 'null'] }
                              onPremisesSyncBehavior: { 
                                type: ['object', 'null']
                                properties: {
                                  isCloudManaged: { type: ['boolean', 'null'] }
                                }
                              }
                            }
                          }
                        }
                        runAfter: {
                          Get_user_details: ['Succeeded']
                        }
                      }
                      // Check if user is member of admin unit
                      Check_admin_unit_membership: {
                        type: 'Http'
                        inputs: {
                          method: 'GET'
                          uri: 'https://graph.microsoft.com/v1.0/directory/administrativeUnits/@{parameters(\'adminUnitId\')}/members?$filter=id eq \'@{variables(\'userId\')}\''
                          authentication: {
                            type: 'ManagedServiceIdentity'
                            audience: 'https://graph.microsoft.com'
                          }
                        }
                        runtimeConfiguration: {
                          contentTransfer: {
                            transferMode: 'Chunked'
                          }
                        }
                        runAfter: {
                          Parse_user_details: ['Succeeded']
                        }
                      }
                      // Get admin unit details for name check
                      Get_admin_unit_details: {
                        type: 'Http'
                        inputs: {
                          method: 'GET'
                          uri: 'https://graph.microsoft.com/v1.0/directory/administrativeUnits/@{parameters(\'adminUnitId\')}?$select=id,displayName'
                          authentication: {
                            type: 'ManagedServiceIdentity'
                            audience: 'https://graph.microsoft.com'
                          }
                        }
                        runAfter: {
                          Parse_user_details: ['Succeeded']
                        }
                      }
                      Parse_admin_unit_details: {
                        type: 'ParseJson'
                        inputs: {
                          content: '@body(\'Get_admin_unit_details\')'
                          schema: {
                            type: 'object'
                            properties: {
                              id: { type: 'string' }
                              displayName: { type: 'string' }
                            }
                          }
                        }
                        runAfter: {
                          Get_admin_unit_details: ['Succeeded']
                        }
                      }
                      Parse_admin_unit_response: {
                        type: 'ParseJson'
                        inputs: {
                          content: '@if(equals(outputs(\'Check_admin_unit_membership\')?[\'statusCode\'], 404), json(\'{"value":[]}\'), body(\'Check_admin_unit_membership\'))'
                          schema: {
                            type: 'object'
                            properties: {
                              value: {
                                type: 'array'
                              }
                            }
                          }
                        }
                        runAfter: {
                          Check_admin_unit_membership: ['Succeeded', 'Failed']
                          Parse_admin_unit_details: ['Succeeded']
                        }
                      }
                      // Only proceed if user is in admin unit
                      Check_if_in_admin_unit: {
                        type: 'If'
                        expression: {
                          and: [
                            {
                              greater: [
                                '@length(body(\'Parse_admin_unit_response\')?[\'value\'])'
                                0
                              ]
                            }
                          ]
                        }
                        actions: {
                          // Log: User is in admin unit
                          Log_user_in_admin_unit: {
                            type: 'ApiConnection'
                            inputs: {
                              host: {
                                connection: {
                                  name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                }
                              }
                              method: 'post'
                              body: '@{json(concat(\'[{"EventType":"UserInAdminUnit","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","AdminUnitId":"\',parameters(\'adminUnitId\'),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                              headers: {
                                'Log-Type': 'HybridUserSync'
                              }
                              path: '/api/logs'
                            }
                            runAfter: {}
                          }
                          // Check if user is already hybrid (has immutableId)
                          Check_if_hybrid: {
                            type: 'If'
                            expression: {
                              not: {
                                equals: [
                                  '@body(\'Parse_user_details\')?[\'onPremisesImmutableId\']'
                                  null
                                ]
                              }
                            }
                            actions: {
                              // User IS hybrid - check if source of authority needs updating
                              Check_if_cloud_managed: {
                                type: 'If'
                                expression: {
                                  and: [
                                    {
                                      equals: [
                                        '@parameters(\'disableSourceOfAuthorityUpdate\')'
                                        false
                                      ]
                                    }
                                    {
                                      equals: [
                                        '@coalesce(body(\'Parse_user_details\')?[\'onPremisesSyncBehavior\']?[\'isCloudManaged\'], false)'
                                        false
                                      ]
                                    }
                                    {
                                      or: [
                                        {
                                          equals: [
                                            '@length(parameters(\'allowedAdminUnitNames\'))'
                                            0
                                          ]
                                        }
                                        {
                                          contains: [
                                            '@parameters(\'allowedAdminUnitNames\')'
                                            '@body(\'Parse_admin_unit_details\')?[\'displayName\']'
                                          ]
                                        }
                                      ]
                                    }
                                  ]
                                }
                                actions: {
                                  // isCloudManaged is false - needs update
                                  Log_setting_source_of_authority: {
                                    type: 'ApiConnection'
                                    inputs: {
                                      host: {
                                        connection: {
                                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                        }
                                      }
                                      method: 'post'
                                      body: '@{json(concat(\'[{"EventType":"SettingSourceOfAuthority","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","ImmutableId":"\',body(\'Parse_user_details\')?[\'onPremisesImmutableId\'],\'","IsCloudManaged":"false","Timestamp":"\',utcNow(),\'"}]\'))}'
                                      headers: {
                                        'Log-Type': 'HybridUserSync'
                                      }
                                      path: '/api/logs'
                                    }
                                    runAfter: {}
                                  }
                                  // Set source of authority to cloud (isCloudManaged=true)
                                  Set_source_of_authority: {
                                    type: 'Http'
                                    inputs: {
                                      method: 'PATCH'
                                      uri: 'https://graph.microsoft.com/beta/users/@{variables(\'userId\')}/onPremisesSyncBehavior'
                                      authentication: {
                                        type: 'ManagedServiceIdentity'
                                        audience: 'https://graph.microsoft.com'
                                      }
                                      headers: {
                                        'Content-Type': 'application/json'
                                      }
                                      body: {
                                        isCloudManaged: true
                                      }
                                    }
                                    runAfter: {
                                      Log_setting_source_of_authority: ['Succeeded']
                                    }
                                  }
                                  // Log successful source of authority change
                                  Log_source_of_authority_success: {
                                    type: 'ApiConnection'
                                    inputs: {
                                      host: {
                                        connection: {
                                          name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                        }
                                      }
                                      method: 'post'
                                      body: '@{json(concat(\'[{"EventType":"SourceOfAuthoritySuccess","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                                      headers: {
                                        'Log-Type': 'HybridUserSync'
                                      }
                                      path: '/api/logs'
                                    }
                                    runAfter: {
                                      Set_source_of_authority: ['Succeeded']
                                    }
                                  }
                                }
                                else: {
                                  actions: {
                                    // Source of authority update skipped - log reason
                                    Log_source_of_authority_skipped: {
                                      type: 'ApiConnection'
                                      inputs: {
                                        host: {
                                          connection: {
                                            name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                          }
                                        }
                                        method: 'post'
                                        body: '@{json(concat(\'[{"EventType":"SourceOfAuthoritySkipped","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","ImmutableId":"\',body(\'Parse_user_details\')?[\'onPremisesImmutableId\'],\'","IsCloudManaged":"\',coalesce(string(body(\'Parse_user_details\')?[\'onPremisesSyncBehavior\']?[\'isCloudManaged\']), \'false\'),\'","AdminUnitName":"\',body(\'Parse_admin_unit_details\')?[\'displayName\'],\'","UpdateDisabled":"\',parameters(\'disableSourceOfAuthorityUpdate\'),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                                        headers: {
                                          'Log-Type': 'HybridUserSync'
                                        }
                                        path: '/api/logs'
                                      }
                                      runAfter: {}
                                    }
                                  }
                                }
                                runAfter: {}
                              }
                            }
                            else: {
                              actions: {
                                // User is NOT hybrid - provision to AD DS
                                Log_provisioning_start: {
                                  type: 'ApiConnection'
                                  inputs: {
                                    host: {
                                      connection: {
                                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                      }
                                    }
                                    method: 'post'
                                    body: '@{json(concat(\'[{"EventType":"ProvisioningStarted","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                                    headers: {
                                      'Log-Type': 'HybridUserSync'
                                    }
                                    path: '/api/logs'
                                  }
                                  runAfter: {}
                                }
                                // Call provisioning API
                                Provision_user_to_ADDS: {
                                  type: 'Http'
                                  inputs: {
                                    method: 'POST'
                                    uri: '@{parameters(\'provisioningApiEndpoint\')}'
                                    authentication: {
                                      type: 'ManagedServiceIdentity'
                                      audience: 'https://graph.microsoft.com'
                                    }
                                    headers: {
                                      'Content-Type': 'application/scim+json'
                                    }
                                    body: {
                                      schemas: [
                                        'urn:ietf:params:scim:api:messages:2.0:BulkRequest'
                                      ]
                                      Operations: [
                                        {
                                          method: 'POST'
                                          bulkId: '@{guid()}'
                                          path: '/Users'
                                          data: {
                                            schemas: [
                                              'urn:ietf:params:scim:schemas:core:2.0:User'
                                              'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'
                                            ]
                                            externalId: '@{if(empty(body(\'Parse_user_details\')?[\'employeeId\']), utcNow(\'yyyyMMddHHmmss\'), body(\'Parse_user_details\')?[\'employeeId\'])}'
                                            userName: '@{body(\'Parse_user_details\')?[\'userPrincipalName\']}'
                                            name: {
                                              givenName: '@{body(\'Parse_user_details\')?[\'givenName\']}'
                                              familyName: '@{body(\'Parse_user_details\')?[\'surname\']}'
                                            }
                                            displayName: '@{body(\'Parse_user_details\')?[\'displayName\']}'
                                            emails: [
                                              {
                                                value: '@{coalesce(body(\'Parse_user_details\')?[\'mail\'], body(\'Parse_user_details\')?[\'userPrincipalName\'])}'
                                                type: 'work'
                                                primary: true
                                              }
                                            ]
                                            active: true
                                            'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User': {
                                              employeeNumber: '@{body(\'Parse_user_details\')?[\'employeeId\']}'
                                              department: '@{body(\'Parse_user_details\')?[\'department\']}'
                                              organization: '@{body(\'Parse_user_details\')?[\'companyName\']}'
                                            }
                                          }
                                        }
                                      ]
                                      failOnErrors: null
                                    }
                                  }
                                  operationOptions: 'DisableAsyncPattern'
                                  runAfter: {
                                    Log_provisioning_start: ['Succeeded']
                                  }
                                }
                                // Log successful provisioning
                                Log_provisioning_success: {
                                  type: 'ApiConnection'
                                  inputs: {
                                    host: {
                                      connection: {
                                        name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                      }
                                    }
                                    method: 'post'
                                    body: '@{json(concat(\'[{"EventType":"ProvisioningSuccess","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                                    headers: {
                                      'Log-Type': 'HybridUserSync'
                                    }
                                    path: '/api/logs'
                                  }
                                  runAfter: {
                                    Provision_user_to_ADDS: ['Succeeded']
                                  }
                                }
                              }
                            }
                            runAfter: {
                              Log_user_in_admin_unit: ['Succeeded']
                            }
                          }
                        }
                        else: {
                          actions: {
                            // Log: User not in admin unit - skip processing
                            Log_user_not_in_admin_unit: {
                              type: 'ApiConnection'
                              inputs: {
                                host: {
                                  connection: {
                                    name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                                  }
                                }
                                method: 'post'
                                body: '@{json(concat(\'[{"EventType":"UserNotInAdminUnit","UserId":"\',variables(\'userId\'),\'","UserPrincipalName":"\',body(\'Parse_user_details\')?[\'userPrincipalName\'],\'","AdminUnitId":"\',parameters(\'adminUnitId\'),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                                headers: {
                                  'Log-Type': 'HybridUserSync'
                                }
                                path: '/api/logs'
                              }
                              runAfter: {}
                            }
                          }
                        }
                        runAfter: {
                          Parse_admin_unit_response: ['Succeeded']
                        }
                      }
                    }
                    runAfter: {
                      Set_user_id: ['Succeeded']
                    }
                  }
                  // Handle errors - write to dead letter and log
                  Process_user_error_handler: {
                    type: 'Scope'
                    actions: {
                      Set_error_flag: {
                        type: 'SetVariable'
                        inputs: {
                          name: 'hasError'
                          value: true
                        }
                        runAfter: {}
                      }
                      Compose_error_details: {
                        type: 'Compose'
                        inputs: {
                          userId: '@{variables(\'userId\')}'
                          error: '@{result(\'Process_user_scope\')}'
                          notification: '@{items(\'For_each_notification\')}'
                          timestamp: '@{utcNow()}'
                        }
                        runAfter: {
                          Set_error_flag: ['Succeeded']
                        }
                      }
                      // Write to dead letter storage
                      Write_to_dead_letter: {
                        type: 'Http'
                        inputs: {
                          method: 'PUT'
                          uri: 'https://@{parameters(\'deadLetterStorageAccount\')}.blob.core.windows.net/@{parameters(\'deadLetterContainer\')}/@{utcNow(\'yyyy-MM-dd_HHmmss\')}_@{variables(\'userId\')}.json'
                          authentication: {
                            type: 'ManagedServiceIdentity'
                            audience: 'https://storage.azure.com/'
                          }
                          headers: {
                            'x-ms-blob-type': 'BlockBlob'
                            'Content-Type': 'application/json'
                          }
                          body: '@outputs(\'Compose_error_details\')'
                        }
                        runAfter: {
                          Compose_error_details: ['Succeeded']
                        }
                      }
                      // Log error
                      Log_error: {
                        type: 'ApiConnection'
                        inputs: {
                          host: {
                            connection: {
                              name: '@parameters(\'$connections\')[\'azureloganalyticsdatacollector\'][\'connectionId\']'
                            }
                          }
                          method: 'post'
                          body: '@{json(concat(\'[{"EventType":"ProcessingError","UserId":"\',variables(\'userId\'),\'","ErrorDetails":"\',base64(string(result(\'Process_user_scope\'))),\'","Timestamp":"\',utcNow(),\'"}]\'))}'
                          headers: {
                            'Log-Type': 'HybridUserSync'
                          }
                          path: '/api/logs'
                        }
                        runAfter: {
                          Write_to_dead_letter: ['Succeeded']
                        }
                      }
                    }
                    runAfter: {
                      Process_user_scope: ['Failed', 'Skipped', 'TimedOut']
                    }
                  }
                }
                runAfter: {
                  Return_accepted_response: ['Succeeded']
                }
              }
            }
          }
          runAfter: {
            Initialize_user_id: ['Succeeded']
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
  name: 'azureloganalyticsdatacollector-${logicAppName}'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Log Analytics Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureloganalyticsdatacollector')
    }
    parameterValues: {
      username: logAnalyticsCustomerId
      password: logAnalyticsPrimaryKey
    }
  }
}

// Diagnostic settings for Logic App
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: logicApp
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

output logicAppId string = logicApp.id
output logicAppPrincipalId string = logicApp.identity.principalId
