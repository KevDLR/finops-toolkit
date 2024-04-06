// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//==============================================================================
// Parameters
//==============================================================================

@description('Required. Name of the FinOps hub instance.')
param hubName string

@description('Required. Name of the Data Factory instance.')
param dataFactoryName string

@description('Required. The name of the Azure Key Vault instance.')
param keyVaultName string

@description('Required. The name of the Azure storage account instance.')
param storageAccountName string

@description('Required. The name of the container where Cost Management data is exported.')
param exportContainerName string

@description('Required. The name of the container where normalized data is ingested.')
param ingestionContainerName string

@description('Required. The name of the container where normalized data is ingested.')
param configContainerName string

@description('Optional. Indicates whether ingested data should be converted to parquet. Default: true.')
param convertToParquet bool = true

@description('Optional. The location to use for the managed identity and deployment script to auto-start triggers. Default = (resource group location).')
param location string = resourceGroup().location

@description('Optional. Remote storage account for ingestion dataset.')
param remoteHubStorageUri string

@description('Optional. Tags to apply to all resources. We will also add the cm-resource-parent tag for improved cost roll-ups in Cost Management.')
param tags object = {}

@description('Optional. Tags to apply to resources based on their resource type. Resource type specific tags will be merged with tags for all resources.')
param tagsByResource object = {}

//------------------------------------------------------------------------------
// Variables
//------------------------------------------------------------------------------

var datasetPropsDelimitedText = {
  columnDelimiter: ','
  compressionLevel: 'Optimal'
  escapeChar: '"'
  firstRowAsHeader: true
  quoteChar: '"'
}
var datasetPropsParquet = {}
var datasetPropsCommon = {
  location: {
    type: 'AzureBlobFSLocation'
    fileName: {
      value: '@{dataset().fileName}'
      type: 'Expression'
    }
    folderPath: {
      value: '@{dataset().folderName}'
      type: 'Expression'
    }
  }
}

var safeExportContainerName = replace('${exportContainerName}', '-', '_')
var safeIngestionContainerName = replace('${ingestionContainerName}', '-', '_')
var safeConfigContainerName = replace('${configContainerName}', '-', '_')

// All hub triggers (used to auto-start)
var fileAddedExportTriggerName = '${safeExportContainerName}_FileAdded'
var updateConfigTriggerName = '${safeConfigContainerName}_SettingsUpdated'
var dailyTriggerName = '${safeConfigContainerName}_DailySchedule'
var monthlyTriggerName = '${safeConfigContainerName}_MonthlySchedule'
var allHubTriggers = [
  fileAddedExportTriggerName
  updateConfigTriggerName
  dailyTriggerName
  monthlyTriggerName
]

// Roles needed to auto-start triggers
var autoStartRbacRoles = [
  '673868aa-7521-48a0-acc6-0f60742d39f5' // Data Factory contributor - https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#data-factory-contributor
  'e40ec5ca-96e0-45a2-b4ff-59039f2c2b59' // Managed Identity Contributor - https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#managed-identity-contributor
]

// Storage roles needed for ADF to create CM exports and process the output
// Does not include roles assignments needed against the export scope
var storageRbacRoles = [
  '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-account-contributor
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#storage-blob-data-contributor
  'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#reader
]

// FocusCost 1.0-preview(v1) columns
var focusCostColumns = [
  { name: 'AvailabilityZone', type: 'String' }
  { name: 'BilledCost', type: 'Decimal' }
  { name: 'BillingAccountId', type: 'String' }
  { name: 'BillingAccountName', type: 'String' }
  { name: 'BillingAccountType', type: 'String' }
  { name: 'BillingCurrency', type: 'String' }
  { name: 'BillingPeriodEnd', type: 'DateTime' }
  { name: 'BillingPeriodStart', type: 'DateTime' }
  { name: 'ChargeCategory', type: 'String' }
  { name: 'ChargeDescription', type: 'String' }
  { name: 'ChargeFrequency', type: 'String' }
  { name: 'ChargePeriodEnd', type: 'DateTime' }
  { name: 'ChargePeriodStart', type: 'DateTime' }
  { name: 'ChargeSubcategory', type: 'String' }
  { name: 'CommitmentDiscountCategory', type: 'String' }
  { name: 'CommitmentDiscountId', type: 'String' }
  { name: 'CommitmentDiscountName', type: 'String' }
  { name: 'CommitmentDiscountType', type: 'String' }
  { name: 'EffectiveCost', type: 'Decimal' }
  { name: 'InvoiceIssuerName', type: 'String' }
  { name: 'ListCost', type: 'Decimal' }
  { name: 'ListUnitPrice', type: 'Decimal' }
  { name: 'PricingCategory', type: 'String' }
  { name: 'PricingQuantity', type: 'Decimal' }
  { name: 'PricingUnit', type: 'String' }
  { name: 'ProviderName', type: 'String' }
  { name: 'PublisherName', type: 'String' }
  { name: 'Region', type: 'String' }
  { name: 'ResourceId', type: 'String' }
  { name: 'ResourceName', type: 'String' }
  { name: 'ResourceType', type: 'String' }
  { name: 'ServiceCategory', type: 'String' }
  { name: 'ServiceName', type: 'String' }
  { name: 'SkuId', type: 'String' }
  { name: 'SkuPriceId', type: 'String' }
  { name: 'SubAccountId', type: 'String' }
  { name: 'SubAccountName', type: 'String' }
  { name: 'SubAccountType', type: 'String' }
  { name: 'Tags', type: 'String' }
  { name: 'UsageQuantity', type: 'Decimal' }
  { name: 'UsageUnit', type: 'String' }
  { name: 'x_AccountName', type: 'String' }
  { name: 'x_AccountOwnerId', type: 'String' }
  { name: 'x_BilledCostInUsd', type: 'Decimal' }
  { name: 'x_BilledUnitPrice', type: 'Decimal' }
  { name: 'x_BillingAccountId', type: 'String' }
  { name: 'x_BillingAccountName', type: 'String' }
  { name: 'x_BillingExchangeRate', type: 'Decimal' }
  { name: 'x_BillingExchangeRateDate', type: 'DateTime' }
  { name: 'x_BillingProfileId', type: 'String' }
  { name: 'x_BillingProfileName', type: 'String' }
  { name: 'x_ChargeId', type: 'String' }
  { name: 'x_CostAllocationRuleName', type: 'String' }
  { name: 'x_CostCenter', type: 'String' }
  { name: 'x_CustomerId', type: 'String' }
  { name: 'x_CustomerName', type: 'String' }
  { name: 'x_EffectiveCostInUsd', type: 'Decimal' }
  { name: 'x_EffectiveUnitPrice', type: 'Decimal' }
  { name: 'x_InvoiceId', type: 'String' }
  { name: 'x_InvoiceIssuerId', type: 'String' }
  { name: 'x_InvoiceSectionId', type: 'String' }
  { name: 'x_InvoiceSectionName', type: 'String' }
  { name: 'x_OnDemandCost', type: 'Decimal' }
  { name: 'x_OnDemandCostInUsd', type: 'Decimal' }
  { name: 'x_OnDemandUnitPrice', type: 'Decimal' }
  { name: 'x_PartnerCreditApplied', type: 'Boolean' }
  { name: 'x_PartnerCreditRate', type: 'Decimal' }
  { name: 'x_PricingBlockSize', type: 'Decimal' }
  { name: 'x_PricingCurrency', type: 'String' }
  { name: 'x_PricingSubcategory', type: 'String' }
  { name: 'x_PricingUnitDescription', type: 'String' }
  { name: 'x_PublisherCategory', type: 'String' }
  { name: 'x_PublisherId', type: 'String' }
  { name: 'x_ResellerId', type: 'String' }
  { name: 'x_ResellerName', type: 'String' }
  { name: 'x_ResourceGroupName', type: 'String' }
  { name: 'x_ResourceType', type: 'String' }
  { name: 'x_ServicePeriodEnd', type: 'DateTime' }
  { name: 'x_ServicePeriodStart', type: 'DateTime' }
  { name: 'x_SkuDescription', type: 'String' }
  { name: 'x_SkuDetails', type: 'String' }
  { name: 'x_SkuIsCreditEligible', type: 'Boolean' }
  { name: 'x_SkuMeterCategory', type: 'String' }
  { name: 'x_SkuMeterId', type: 'String' }
  { name: 'x_SkuMeterName', type: 'String' }
  { name: 'x_SkuMeterSubcategory', type: 'String' }
  { name: 'x_SkuOfferId', type: 'String' }
  { name: 'x_SkuOrderId', type: 'String' }
  { name: 'x_SkuOrderName', type: 'String' }
  { name: 'x_SkuPartNumber', type: 'String' }
  { name: 'x_SkuRegion', type: 'String' }
  { name: 'x_SkuServiceFamily', type: 'String' }
  { name: 'x_SkuTerm', type: 'String' }
  { name: 'x_SkuTier', type: 'String' }
]
var focusCostMappings = [for i in range(0, length(focusCostColumns)): {
  source: { name: focusCostColumns[i].name, type: focusCostColumns[i].type }
  sink: { name: focusCostColumns[i].name }
}]

//==============================================================================
// Resources
//==============================================================================

// Get data factory instance
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: dataFactoryName
}

// Get storage account instance
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

// Get keyvault instance
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

module azuretimezones 'azuretimezones.bicep' = {
  name: 'azuretimezones'
  params: {
    location: location
  }
}

//------------------------------------------------------------------------------
// Identities and RBAC
//------------------------------------------------------------------------------

// Create managed identity to start/stop triggers
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${dataFactory.name}_triggerManager'
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.ManagedIdentity/userAssignedIdentities') ? tagsByResource['Microsoft.ManagedIdentity/userAssignedIdentities'] : {})
}

resource identityRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in autoStartRbacRoles: {
  name: guid(dataFactory.id, role, identity.id)
  scope: dataFactory
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Create managed identity to manage exports in cost management
resource pipelineIdentityRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in storageRbacRoles: {
  name: guid(storageAccount.id, role, dataFactory.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role)
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}]

//------------------------------------------------------------------------------
// Delete old triggers and pipelines
//------------------------------------------------------------------------------

resource deleteOldResources 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${dataFactory.name}_deleteOldResources'
  // chinaeast2 is the only region in China that supports deployment scripts
  location: startsWith(location, 'china') ? 'chinaeast2' : location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  kind: 'AzurePowerShell'
  dependsOn: [
    identityRoleAssignments
  ]
  tags: union(tags, contains(tagsByResource, 'Microsoft.Resources/deploymentScripts') ? tagsByResource['Microsoft.Resources/deploymentScripts'] : {})
  properties: {
    azPowerShellVersion: '8.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    scriptContent: loadTextContent('./scripts/Remove-OldResources.ps1')
    environmentVariables: [
      {
        name: 'DataFactorySubscriptionId'
        value: subscription().id
      }
      {
        name: 'DataFactoryResourceGroup'
        value: resourceGroup().name
      }
      {
        name: 'DataFactoryName'
        value: dataFactory.name
      }
    ]
  }
}

//------------------------------------------------------------------------------
// Stop all triggers before deploying
//------------------------------------------------------------------------------

resource stopTriggers 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${dataFactory.name}_stopTriggers'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  kind: 'AzurePowerShell'
  dependsOn: [
    identityRoleAssignments
  ]
  tags: tags
  properties: {
    azPowerShellVersion: '8.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    scriptContent: loadTextContent('./scripts/Start-Triggers.ps1')
    arguments: '-Stop'
    environmentVariables: [
      {
        name: 'DataFactorySubscriptionId'
        value: subscription().id
      }
      {
        name: 'DataFactoryResourceGroup'
        value: resourceGroup().name
      }
      {
        name: 'DataFactoryName'
        value: dataFactory.name
      }
      {
        name: 'Triggers'
        value: join(allHubTriggers, '|')
      }
    ]
  }
}

//------------------------------------------------------------------------------
// Linked services
//------------------------------------------------------------------------------

resource linkedService_keyVault 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: keyVault.name
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {}
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: reference('Microsoft.KeyVault/vaults/${keyVault.name}', '2023-02-01').vaultUri
    }
  }
}

resource linkedService_storageAccount 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: storageAccount.name
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {}
    type: 'AzureBlobFS'
    typeProperties: {
      url: reference('Microsoft.Storage/storageAccounts/${storageAccount.name}', '2021-08-01').primaryEndpoints.dfs
    }
  }
}

resource linkedService_remoteHubStorage 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = if (!empty(remoteHubStorageUri)) {
  name: 'remoteHubStorage'
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {}
    type: 'AzureBlobFS'
    typeProperties: {
      url: remoteHubStorageUri
      accountKey: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: linkedService_keyVault.name
          type: 'LinkedServiceReference'
        }
        secretName: '${toLower(hubName)}-storage-key'
      }
    }
  }
}

//------------------------------------------------------------------------------
// Datasets
//------------------------------------------------------------------------------

resource dataset_config 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: safeConfigContainerName
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {
      fileName: {
        type: 'String'
        defaultValue: 'settings.json'
      }
      folderName: {
        type: 'String'
        defaultValue: configContainerName
      }
    }
    type: 'Json'
    typeProperties: datasetPropsCommon
    linkedServiceName: {
      parameters: {}
      referenceName: linkedService_storageAccount.name
      type: 'LinkedServiceReference'
    }
  }
}

resource dataset_msexports 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: safeExportContainerName
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {
      fileName: {
        type: 'String'
      }
      folderName: {
        type: 'String'
      }
    }
    type: 'DelimitedText'
    typeProperties: union(datasetPropsCommon, datasetPropsDelimitedText, { compressionCodec: 'none' })
    linkedServiceName: {
      parameters: {}
      referenceName: linkedService_storageAccount.name
      type: 'LinkedServiceReference'
    }
  }
}

resource dataset_ingestion 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: safeIngestionContainerName
  parent: dataFactory
  properties: {
    annotations: []
    parameters: {
      fileName: {
        type: 'String'
      }
      folderName: {
        type: 'String'
      }
    }
    type: any(convertToParquet ? 'Parquet' : 'DelimitedText')
    typeProperties: union(
      datasetPropsCommon,
      convertToParquet ? datasetPropsParquet : datasetPropsDelimitedText,
      { compressionCodec: 'gzip' }
    )
    linkedServiceName: {
      parameters: {}
      referenceName: empty(remoteHubStorageUri) ? linkedService_storageAccount.name : linkedService_remoteHubStorage.name
      type: 'LinkedServiceReference'
    }
  }
}

//------------------------------------------------------------------------------
// Triggers
//------------------------------------------------------------------------------

// Create trigger
resource trigger_FileAdded 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  name: fileAddedExportTriggerName
  parent: dataFactory
  dependsOn: [
    stopTriggers
  ]
  properties: {
    annotations: []
    pipelines: [
      {
        pipelineReference: {
          referenceName: pipeline_ExecuteETL.name
          type: 'PipelineReference'
        }
        parameters: {
          folderName: '@triggerBody().folderPath'
          fileName: '@triggerBody().fileName'
        }
      }
    ]
    type: 'BlobEventsTrigger'
    typeProperties: {
      blobPathBeginsWith: '/${exportContainerName}/blobs/'
      blobPathEndsWith: '.csv'
      ignoreEmptyBlobs: true
      scope: storageAccount.id
      events: [
        'Microsoft.Storage.BlobCreated'
      ]
    }
  }
}

resource trigger_SettingsUpdated 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  name: updateConfigTriggerName
  parent: dataFactory
  dependsOn: [
    stopTriggers
  ]
  properties: {
    annotations: []
    pipelines: [
      {
        pipelineReference: {
          referenceName: pipeline_ConfigureExports.name
          type: 'PipelineReference'
        }
      }
    ]
    type: 'BlobEventsTrigger'
    typeProperties: {
      blobPathBeginsWith: '/${configContainerName}/blobs/'
      blobPathEndsWith: 'settings.json'
      ignoreEmptyBlobs: true
      scope: storageAccount.id
      events: [
        'Microsoft.Storage.BlobCreated'
      ]
    }
  }
}

resource trigger_DailySchedule 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  name: dailyTriggerName
  parent: dataFactory
  dependsOn: [
    stopTriggers
  ]
  properties: {
    pipelines: [
      {
        pipelineReference: {
          referenceName: pipeline_ExportData.name
          type: 'PipelineReference'
        }
        parameters: {
          Recurrence: 'Daily'
        }
      }
    ]
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: 'Hour'
        interval: 24
        startTime: '2023-01-01T01:01:00'
        timeZone: azuretimezones.outputs.Timezone
      }
    }
  }
}

resource trigger_MonthlySchedule 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  name: monthlyTriggerName
  parent: dataFactory
  dependsOn: [
    stopTriggers
  ]
  properties: {
    pipelines: [
      {
        pipelineReference: {
          referenceName: pipeline_ExportData.name
          type: 'PipelineReference'
        }
        parameters: {
          Recurrence: 'Monthly'
        }
      }
    ]
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: 'Month'
        interval: 1
        startTime: '2023-01-05T01:11:00'
        timeZone: azuretimezones.outputs.Timezone
        schedule: {
          monthDays: [
            5
            19
          ]
        }
      }
    }
  }
}

//------------------------------------------------------------------------------
// Pipelines
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// config_BackfillData pipeline
//------------------------------------------------------------------------------
@description('Runs the backfill job for each month based on retention settings.')
resource pipeline_BackfillData 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeConfigContainerName}_BackfillData'
  parent: dataFactory
  properties: {
    activities: [
      {
        name: 'Get Config'
        type: 'Lookup'
        dependsOn: []
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'JsonSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'JsonReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_config.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@variables(\'fileName\')'
                type: 'Expression'
              }
              folderName: {
                value: '@variables(\'folderName\')'
                type: 'Expression'
              }
            }
          }
        }
      }
      {
        name: 'Set backfill end date'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Get Config'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'endDate'
          value: {
            value: '@addDays(startOfMonth(utcNow()), -1)'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set backfill start date'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Get Config'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'startDate'
          value: {
            value: '@subtractFromTime(startOfMonth(utcNow()), activity(\'Get Config\').output.firstRow.retention.ingestion.months, \'Month\')'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set export start date'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set backfill start date'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'thisMonth'
          value: {
            value: '@startOfMonth(variables(\'endDate\'))'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set export end date'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set export start date'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'nextMonth'
          value: {
            value: '@startOfMonth(subtractFromTime(variables(\'thisMonth\'), 1, \'Month\'))'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Every Month'
        type: 'Until'
        dependsOn: [
          {
            activity: 'Set export end date'
            dependencyConditions: [
              'Succeeded'
            ]
          }
          {
            activity: 'Set backfill end date'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          expression: {
            value: '@less(variables(\'thisMonth\'), variables(\'startDate\'))'
            type: 'Expression'
          }
          activities: [
            {
              name: 'Update export start date'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Backfill data'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'thisMonth'
                value: {
                  value: '@variables(\'nextMonth\')'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Update export end date'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Update export start date'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'nextMonth'
                value: {
                  value: '@subtractFromTime(variables(\'thisMonth\'), 1, \'Month\')'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Backfill data'
              type: 'ExecutePipeline'
              dependsOn: []
              userProperties: []
              typeProperties: {
                pipeline: {
                  referenceName: pipeline_RunBackfill.name
                  type: 'PipelineReference'
                }
                waitOnCompletion: true
                parameters: {
                  StartDate: {
                    value: '@variables(\'thisMonth\')'
                    type: 'Expression'
                  }
                  EndDate: {
                    value: '@addDays(addToTime(variables(\'thisMonth\'), 1, \'Month\'), -1)'
                    type: 'Expression'
                  }
                }
              }
            }
          ]
          timeout: '0.12:00:00'
        }
      }
    ]
    concurrency: 1
    variables: {
      exportName: {
        type: 'String'
      }
      storageAccountId: {
        type: 'String'
        defaultValue: storageAccount.id
      }
      finOpsHub: {
        type: 'String'
        defaultValue: hubName
      }
      resourceManagementUri: {
        type: 'String'
        defaultValue: environment().resourceManager
      }
      fileName: {
        type: 'String'
        defaultValue: 'settings.json'
      }
      folderName: {
        type: 'String'
        defaultValue: configContainerName
      }
      endDate: {
        type: 'String'
      }
      startDate: {
        type: 'String'
      }
      thisMonth: {
        type: 'String'
      }
      nextMonth: {
        type: 'String'
      }
    }
  }
}

//------------------------------------------------------------------------------
// config_RunBackfill pipeline
// Triggered by config_BackfillData pipeline
//------------------------------------------------------------------------------
@description('Creates and triggers exports for all defined scopes for the specified date range.')
resource pipeline_RunBackfill 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeConfigContainerName}_RunBackfill'
  parent: dataFactory
  properties: {
    activities: [
      {
        name: 'Get Config'
        type: 'Lookup'
        dependsOn: []
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'JsonSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'JsonReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_config.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@variables(\'fileName\')'
                type: 'Expression'
              }
              folderName: {
                value: '@variables(\'folderName\')'
                type: 'Expression'
              }
            }
          }
        }
      }
      {
        name: 'ForEach Export Scope'
        type: 'ForEach'
        dependsOn: [
          {
            activity: 'Get Config'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          items: {
            value: '@activity(\'Get Config\').output.firstRow.scopes'
            type: 'Expression'
          }
          isSequential: true
          activities: [
            {
              name: 'Create or update backfill amortized export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set backfill amortized export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n      "properties": {\n        "schedule": {\n          "status": "Inactive",\n          "recurrence": "daily",\n          "recurrencePeriod": {\n            "from": "2099-06-01T00:00:00Z",\n            "to": "2099-10-31T00:00:00Z"\n          }\n        },\n        "partitionData": "true",\n        "format": "Csv",\n        "deliveryInfo": {\n          "destination": {\n            "resourceId": "@{variables(\'storageAccountId\')}",\n            "container": "${exportContainerName}",\n            "rootFolderPath": "@{item().scope}"\n          }\n        },\n        "definition": {\n          "type": "amortizedcost",\n          "timeframe": "Custom",\n          "timePeriod" : {\n            "from" : "@{pipeline().parameters.StartDate}",\n            "to" : "@{pipeline().parameters.EndDate}"\n          },\n          "dataSet": {\n            "granularity": "Daily"\n          }\n        }\n      }\n    }'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'resourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set backfill amortized export name'
              type: 'SetVariable'
              dependsOn: []
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'finOpsHub\'), \'-custom-amortizedcost\'))'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Trigger backfill amortized export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Create or update backfill amortized export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 1
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}/run?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'POST'
                body: '{}'
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'resourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Create or update backfill actual export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set backfill actual export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n      "properties": {\n        "schedule": {\n          "status": "Inactive",\n          "recurrence": "daily",\n          "recurrencePeriod": {\n            "from": "2099-06-01T00:00:00Z",\n            "to": "2099-10-31T00:00:00Z"\n          }\n        },\n        "partitionData": "true",\n        "format": "Csv",\n        "deliveryInfo": {\n          "destination": {\n            "resourceId": "@{variables(\'storageAccountId\')}",\n            "container": "${exportContainerName}",\n            "rootFolderPath": "@{item().scope}"\n          }\n        },\n        "definition": {\n          "type": "actualcost",\n          "timeframe": "Custom",\n          "timePeriod" : {\n            "from" : "@{pipeline().parameters.StartDate}",\n            "to" : "@{pipeline().parameters.EndDate}"\n          },\n          "dataSet": {\n            "granularity": "Daily"\n          }\n        }\n      }\n    }'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'resourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set backfill actual export name'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Trigger backfill amortized export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'finOpsHub\'), \'-custom-actualcost\'))'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Trigger backfill actual export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Create or update backfill actual export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 1
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}/run?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'POST'
                body: '{}'
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'resourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
          ]
        }
      }
    ]
    concurrency: 1
    parameters: {
      StartDate: {
        type: 'string'
      }
      EndDate: {
        type: 'string'
      }
    }
    variables: {
      exportName: {
        type: 'String'
      }
      storageAccountId: {
        type: 'String'
        defaultValue: storageAccount.id
      }
      finOpsHub: {
        type: 'String'
        defaultValue: hubName
      }
      resourceManagementUri: {
        type: 'String'
        defaultValue: environment().resourceManager
      }
      fileName: {
        type: 'String'
        defaultValue: 'settings.json'
      }
      folderName: {
        type: 'String'
        defaultValue: configContainerName
      }
    }
  }
}

//------------------------------------------------------------------------------
// Microsoft Cost Management scheduled exports
// Triggered by config_DailySchedule/MonthlySchedule triggers
//------------------------------------------------------------------------------
@description('Gets a list of all Cost Management exports configured for this hub based on the scopes defined in settings.json, then runs each export using the config_RunExports pipeline.')
resource pipeline_ExportData 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeConfigContainerName}_ExportData'
  parent: dataFactory
  properties: {
    activities: [
      {
        name: 'Get Config'
        type: 'Lookup'
        dependsOn: []
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'JsonSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'JsonReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_config.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@variables(\'fileName\')'
                type: 'Expression'
              }
              folderName: {
                value: '@variables(\'folderName\')'
                type: 'Expression'
              }
            }
          }
        }
      }
      {
        name: 'ForEach Export Scope'
        type: 'ForEach'
        dependsOn: [
          {
            activity: 'Get Config'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          items: {
            value: '@activity(\'Get Config\').output.firstRow.scopes'
            type: 'Expression'
          }
          isSequential: true
          activities: [
            {
              name: 'Get exports for scope'
              type: 'WebActivity'
              dependsOn: []
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports?api-version=2023-03-01'
                  type: 'Expression'
                }
                method: 'GET'
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'resourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Run exports for scope'
              type: 'ExecutePipeline'
              dependsOn: [
                {
                  activity: 'Get exports for scope'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                pipeline: {
                  referenceName: pipeline_RunExports.name
                  type: 'PipelineReference'
                }
                waitOnCompletion: true
                parameters: {
                  ExportScopes: {
                    value: '@activity(\'Get exports for scope\').output.value'
                    type: 'Expression'
                  }
                  Recurrence: {
                    value: '@pipeline().parameters.Recurrence'
                    type: 'Expression'
                  }
                }
              }
            }
          ]
        }
      }
    ]
    concurrency: 1
    parameters: {
      Recurrence: {
        type: 'string'
        defaultValue: 'Daily'
      }
    }
    variables: {
      fileName: {
        type: 'String'
        defaultValue: 'settings.json'
      }
      folderName: {
        type: 'String'
        defaultValue: configContainerName
      }
      finOpsHub: {
        type: 'String'
        defaultValue: hubName
      }
      resourceManagementUri: {
        type: 'String'
        defaultValue: environment().resourceManager
      }
    }
  }
}

//------------------------------------------------------------------------------
// Microsoft Cost Management scheduled exports
// Triggered by pipeline_ExportData pipeline
//------------------------------------------------------------------------------
@description('Runs the specified Cost Management exports.')
resource pipeline_RunExports 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeConfigContainerName}_RunExports'
  parent: dataFactory
  dependsOn: [
    dataset_config
  ]
  properties: {
    activities: [
      {
        name: 'ForEach export scope'
        type: 'ForEach'
        dependsOn: []
        userProperties: []
        typeProperties: {
          items: {
            value: '@pipeline().parameters.exportScopes'
            type: 'Expression'
          }
          isSequential: true
          activities: [
            {
              name: 'If scheduled'
              type: 'IfCondition'
              dependsOn: []
              userProperties: []
              typeProperties: {
                expression: {
                  value: '@equals(tolower(item().properties.schedule.recurrence), toLower(pipeline().parameters.Recurrence))'
                  type: 'Expression'
                }
                ifTrueActivities: [
                  {
                    name: 'Trigger export'
                    type: 'WebActivity'
                    dependsOn: []
                    policy: {
                      timeout: '0.00:05:00'
                      retry: 1
                      retryIntervalInSeconds: 30
                      secureOutput: false
                      secureInput: false
                    }
                    userProperties: []
                    typeProperties: {
                      url: {
                        value: '@{variables(\'resourceManagementUri\')}/@{item().id}/run?api-version=2023-03-01'
                        type: 'Expression'
                      }
                      method: 'POST'
                      body: '{}'
                      authentication: {
                        type: 'MSI'
                        resource: {
                          value: '@variables(\'resourceManagementUri\')'
                          type: 'Expression'
                        }
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    concurrency: 1
    parameters: {
      ExportScopes: {
        type: 'array'
      }
      Recurrence: {
        type: 'string'
        defaultValue: 'Daily'
      }
    }
    variables: {
      resourceManagementUri: {
        type: 'String'
        defaultValue: environment().resourceManager
      }
    }
  }
}

//------------------------------------------------------------------------------
// msexports_ConfigureExports pipeline
// Triggered by config_SettingsUpdated trigger
//------------------------------------------------------------------------------
@description('Creates Cost Management exports for all scopes.')
resource pipeline_ConfigureExports 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeConfigContainerName}_ConfigureExports'
  parent: dataFactory
  properties: {
    activities: [
      {
        name: 'Get Config'
        type: 'Lookup'
        dependsOn: []
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'JsonSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'JsonReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_config.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@variables(\'fileName\')'
                type: 'Expression'
              }
              folderName: {
                value: '@variables(\'folderName\')'
                type: 'Expression'
              }
            }
          }
        }
      }
      {
        name: 'ForEach Export Scope'
        type: 'ForEach'
        dependsOn: [
          {
            activity: 'Get Config'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          items: {
            value: '@activity(\'Get Config\').output.firstRow.scopes'
            type: 'Expression'
          }
          isSequential: true
          activities: [
            {
              name: 'Create or update open month amortized export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set open month amortized export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'resourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n  "properties": {\n    "schedule": {\n      "status": "Inactive",\n      "recurrence": "Daily",\n      "recurrencePeriod": {\n        "from": "@{utcNow()}",\n        "to": "2099-12-31T00:00:00Z"\n      }\n    },\n    "partitionData": "True",\n    "format": "Csv",\n    "deliveryInfo": {\n      "destination": {\n        "resourceId": "@{variables(\'StorageAccountId\')}",\n        "container": "${exportContainerName}",\n        "rootFolderPath": "@{item().scope}"\n      }\n    },\n    "definition": {\n      "type": "amortizedcost",\n      "timeframe": "BillingMonthToDate",\n      "dataSet": {\n        "granularity": "Daily"\n      }\n    }\n  }\n}'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'ResourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set open month amortized export name'
              type: 'SetVariable'
              dependsOn: []
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'FinOpsHub\'), \'-daily-amortizedcost\'))'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Create or update closed month amortized export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set closed month amortized export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'ResourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n  "properties": {\n    "schedule": {\n      "status": "Inactive",\n      "recurrence": "Monthly",\n      "recurrencePeriod": {\n        "from": "@{utcNow()}",\n        "to": "2099-12-31T00:00:00Z"\n      }\n    },\n    "partitionData": "True",\n    "format": "Csv",\n    "deliveryInfo": {\n      "destination": {\n        "resourceId": "@{variables(\'StorageAccountId\')}",\n        "container": "${exportContainerName}",\n        "rootFolderPath": "@{item().scope}"\n      }\n    },\n    "definition": {\n      "type": "amortizedcost",\n      "timeframe": "TheLastBillingMonth",\n      "dataSet": {\n        "granularity": "Daily"\n      }\n    }\n  }\n}'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'ResourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set closed month amortized export name'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Create or update open month amortized export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'FinOpsHub\'), \'-monthly-amortizedcost\'))'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Create or update open month actuals export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set open month actuals export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'ResourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n  "properties": {\n    "schedule": {\n      "status": "Inactive",\n      "recurrence": "Daily",\n      "recurrencePeriod": {\n        "from": "@{utcNow()}",\n        "to": "2099-12-31T00:00:00Z"\n      }\n    },\n    "partitionData": "True",\n    "format": "Csv",\n    "deliveryInfo": {\n      "destination": {\n        "resourceId": "@{variables(\'StorageAccountId\')}",\n        "container": "${exportContainerName}",\n        "rootFolderPath": "@{item().scope}"\n      }\n    },\n    "definition": {\n      "type": "actualcost",\n      "timeframe": "BillingMonthToDate",\n      "dataSet": {\n        "granularity": "Daily"\n      }\n    }\n  }\n}'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'ResourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set open month actuals export name'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Create or update closed month amortized export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'FinOpsHub\'), \'-daily-actualcost\'))'
                  type: 'Expression'
                }
              }
            }
            {
              name: 'Create or update closed month actuals export'
              type: 'WebActivity'
              dependsOn: [
                {
                  activity: 'Set closed month actuals export name'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              policy: {
                timeout: '0.00:05:00'
                retry: 2
                retryIntervalInSeconds: 30
                secureOutput: false
                secureInput: false
              }
              userProperties: []
              typeProperties: {
                url: {
                  value: '@{variables(\'ResourceManagementUri\')}@{item().scope}/providers/Microsoft.CostManagement/exports/@{variables(\'exportName\')}?api-version=2021-10-01'
                  type: 'Expression'
                }
                method: 'PUT'
                body: {
                  value: '{\n  "properties": {\n    "schedule": {\n      "status": "Inactive",\n      "recurrence": "Monthly",\n      "recurrencePeriod": {\n        "from": "@{utcNow()}",\n        "to": "2099-12-31T00:00:00Z"\n      }\n    },\n    "partitionData": "True",\n    "format": "Csv",\n    "deliveryInfo": {\n      "destination": {\n        "resourceId": "@{variables(\'StorageAccountId\')}",\n        "container": "${exportContainerName}",\n        "rootFolderPath": "@{item().scope}"\n      }\n    },\n    "definition": {\n      "type": "actualcost",\n      "timeframe": "TheLastBillingMonth",\n      "dataSet": {\n        "granularity": "Daily"\n      }\n    }\n  }\n}'
                  type: 'Expression'
                }
                authentication: {
                  type: 'MSI'
                  resource: {
                    value: '@variables(\'ResourceManagementUri\')'
                    type: 'Expression'
                  }
                }
              }
            }
            {
              name: 'Set closed month actuals export name'
              type: 'SetVariable'
              dependsOn: [
                {
                  activity: 'Create or update open month actuals export'
                  dependencyConditions: [
                    'Succeeded'
                  ]
                }
              ]
              userProperties: []
              typeProperties: {
                variableName: 'exportName'
                value: {
                  value: '@toLower(concat(variables(\'FinOpsHub\'), \'-monthly-actualcost\'))'
                  type: 'Expression'
                }
              }
            }
          ]
        }
      }
    ]
    concurrency: 1
    variables: {
      exportName: {
        type: 'String'
      }
      exportScope: {
        type: 'String'
      }
      storageAccountId: {
        type: 'String'
        defaultValue: storageAccount.id
      }
      finOpsHub: {
        type: 'String'
        defaultValue: hubName
      }
      resourceManagementUri: {
        type: 'String'
        defaultValue: environment().resourceManager
      }
      fileName: {
        type: 'String'
        defaultValue: 'settings.json'
      }
      folderName: {
        type: 'String'
        defaultValue: configContainerName
      }
    }
  }
}

//------------------------------------------------------------------------------
// msexports_ExecuteETL pipeline
// Triggered by msexports_FileAdded trigger
//------------------------------------------------------------------------------
@description('Queues the msexports_ETL_ingestion pipeline.')
resource pipeline_ExecuteETL 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeExportContainerName}_ExecuteETL'
  parent: dataFactory
  properties: {
    activities: [
      {
        name: 'Execute'
        type: 'ExecutePipeline'
        dependsOn: []
        userProperties: []
        typeProperties: {
          pipeline: {
            referenceName: pipeline_ToIngestion.name
            type: 'PipelineReference'
          }
          waitOnCompletion: false
          parameters: {
            folderName: {
              value: '@pipeline().parameters.folderName'
              type: 'Expression'
            }
            fileName: {
              value: '@pipeline().parameters.fileName'
              type: 'Expression'
            }
          }
        }
      }
    ]
    parameters: {
      folderName: {
        type: 'string'
      }
      fileName: {
        type: 'string'
      }
    }
    annotations: []
  }
}

//------------------------------------------------------------------------------
// msexports_ETL_ingestion pipeline
// Trigger: msexports_ExecuteETL
//------------------------------------------------------------------------------
@description('Transforms CSV data to a standard schema and converts to Parquet.')
resource pipeline_ToIngestion 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: '${safeExportContainerName}_ETL_${safeIngestionContainerName}'
  parent: dataFactory
  properties: {
    activities: [
      // (start) -> Wait -> FolderArray -> Scope -> Metric -> Date -> File -> Folder -> Delete Target -> Convert CSV -> Delete CSV -> (end)
      // Wait
      {
        name: 'Wait'
        type: 'Wait'
        dependsOn: []
        userProperties: []
        typeProperties: {
          waitTimeInSeconds: 60
        }
      }
      // Set FolderArray
      {
        name: 'Set FolderArray'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Wait'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'folderArray'
          value: {
            value: '@split(pipeline().parameters.folderName, \'/\')'
            type: 'Expression'
          }
        }
      }
      // Set FolderCount
      {
        name: 'Set FolderCount'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set FolderArray'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        policy: {
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          variableName: 'folderCount'
          value: '@length(split(pipeline().parameters.folderName, \'/\'))'
        }
      }
      // Set SecondToLastFolder
      {
        name: 'Set SecondToLastFolder'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set FolderCount'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        policy: {
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          variableName: 'secondToLastFolder'
          value: '@variables(\'folderArray\')[sub(variables(\'folderCount\'), 2)]'
        }
      }
      // Set ThirdToLastFolder
      {
        name: 'Set ThirdToLastFolder'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set SecondToLastFolder'
            dependencyConditions: [ 'Succeeded' ]
          }
        ]
        policy: {
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          variableName: 'thirdToLastFolder'
          value: '@variables(\'folderArray\')[sub(variables(\'folderCount\'), 3)]'
        }
      }
      // Set FourthToLastFolder
      {
        name: 'Set FourthToLastFolder'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set ThirdToLastFolder'
            dependencyConditions: [ 'Succeeded' ]
          }
        ]
        policy: {
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          variableName: 'fourthToLastFolder'
          value: '@variables(\'folderArray\')[sub(variables(\'folderCount\'), 4)]'
        }
      }
      // Set Scope
      {
        name: 'Set Scope'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set FourthToLastFolder'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'scope'
          value: {
            value: '@replace(split(pipeline().parameters.folderName, if(greater(length(variables(\'secondToLastFolder\')), 12), variables(\'thirdToLastFolder\'), variables(\'fourthToLastFolder\')))[0], \'${exportContainerName}\', \'${ingestionContainerName}\')'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set Metric'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set Scope'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'metric'
          value: {
            // TODO: Parse metric out of the manifest file @ msexports/<scope>/<export-name>/<date-range>/[<timestamp?>/]<guid>/manifest.json
            value: 'focuscost'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set Date'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set Metric'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'date'
          value: {
            value: '@substring(if(greater(length(variables(\'secondToLastFolder\')), 12), variables(\'secondToLastFolder\'), variables(\'thirdToLastFolder\')), 0, 6)'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set Destination File Name'
        description: ''
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set Date'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'destinationFile'
          value: {
            value: '@replace(pipeline().parameters.fileName, \'.csv\', \'.parquet\')'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Set Destination Folder Name'
        type: 'SetVariable'
        dependsOn: [
          {
            activity: 'Set Destination File Name'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        userProperties: []
        typeProperties: {
          variableName: 'destinationFolder'
          value: {
            value: '@replace(concat(variables(\'scope\'),variables(\'date\'),\'/\',variables(\'metric\')),\'//\',\'/\')'
            type: 'Expression'
          }
        }
      }
      {
        name: 'Delete Target'
        type: 'Delete'
        dependsOn: [
          {
            activity: 'Load Schema Mappings'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          dataset: {
            referenceName: dataset_ingestion.name
            type: 'DatasetReference'
            parameters: {
              folderName: {
                value: '@variables(\'destinationFolder\')'
                type: 'Expression'
              }
              fileName: {
                value: '@variables(\'destinationFile\')'
                type: 'Expression'
              }
            }
          }
          enableLogging: false
          storeSettings: {
            type: 'AzureBlobFSReadSettings'
            recursive: true
            enablePartitionDiscovery: false
          }
        }
      }
      {
        name: 'Convert File'
        type: 'Copy'
        dependsOn: [
          {
            activity: 'Delete Target'
            dependencyConditions: [ 'Completed' ]
          }
        ]
        policy: {
          timeout: '0.00:05:00'
          retry: 0
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'DelimitedTextSource'
            additionalColumns: {
              type: 'Expression'
              value: '@activity(\'Load Schema Mappings\').output.firstRow.additionalColumns'
            }
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'DelimitedTextReadSettings'
            }
          }
          sink: {
            type: 'ParquetSink'
            storeSettings: {
              type: 'AzureBlobFSWriteSettings'
            }
            formatSettings: {
              type: 'ParquetWriteSettings'
              fileExtension: '.parquet'
            }
          }
          enableStaging: false
          parallelCopies: 1
          validateDataConsistency: false
          translator: {
            type: 'TabularTranslator'
            mappings: focusCostMappings
          }
        }
        inputs: [
          {
            referenceName: dataset_msexports.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@pipeline().parameters.fileName'
                type: 'Expression'
              }
              folderName: {
                value: '@pipeline().parameters.folderName'
                type: 'Expression'
              }
            }
          }
        ]
        outputs: [
          {
            referenceName: dataset_ingestion.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@variables(\'destinationFile\')'
                type: 'Expression'
              }
              folderName: {
                value: '@variables(\'destinationFolder\')'
                type: 'Expression'
              }
            }
          }
        ]
      }
      {
        name: 'Read first row'
        type: 'Lookup'
        dependsOn: [
          {
            activity: 'Set Destination Folder Name'
            dependencyConditions: [
              'Completed'
            ]
          }
        ]
        policy: {
          timeout: '0.12:00:00'
          retry: 0
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'DelimitedTextSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'DelimitedTextReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_msexports.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@pipeline().parameters.fileName'
                type: 'Expression'
              }
              folderName: {
                value: '@pipeline().parameters.folderName'
                type: 'Expression'
              }
            }
          }
        }
      }
      {
        name: 'Detect EA Schema'
        type: 'IfCondition'
        dependsOn: [
          {
            activity: 'Read first row'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          expression: {
            value: '@and(not(empty(activity(\'Read first row\').output.firstRow.AccountName)), not(empty(activity(\'Read first row\').output.firstRow.CostInBillingCurrency)))'
            type: 'Expression'
          }
          ifTrueActivities: [
            {
              name: 'Set EA schema'
              type: 'SetVariable'
              dependsOn: []
              userProperties: []
              typeProperties: {
                variableName: 'detectedSchema'
                value: {
                  value: 'ea'
                  type: 'Expression'
                }
              }
            }
          ]
        }
      }
      {
        name: 'Detect MCA Schema'
        type: 'IfCondition'
        dependsOn: [
          {
            activity: 'Detect EA Schema'
            dependencyConditions: [
              'Completed'
            ]
          }
        ]
        userProperties: []
        typeProperties: {
          expression: {
            value: '@and(not(empty(activity(\'Read first row\').output.firstRow.costInBillingCurrency)), not(empty(activity(\'Read first row\').output.firstRow.costInPricingCurrency)))'
            type: 'Expression'
          }
          ifTrueActivities: [
            {
              name: 'Set MCA schema'
              type: 'SetVariable'
              dependsOn: []
              userProperties: []
              typeProperties: {
                variableName: 'detectedSchema'
                value: {
                  value: 'mca'
                  type: 'Expression'
                }
              }
            }
          ]
        }
      }
      {
        name: 'Load Schema Mappings'
        type: 'Lookup'
        dependsOn: [
          {
            activity: 'Detect MCA Schema'
            dependencyConditions: [
              'Completed'
            ]
          }
        ]
        policy: {
          timeout: '0.12:00:00'
          retry: 0
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'JsonSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'JsonReadSettings'
            }
          }
          dataset: {
            referenceName: dataset_config.name
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: 'schema_@{toLower(variables(\'detectedSchema\'))}_normalized.json'
                type: 'Expression'
              }
              folderName: configContainerName
            }
          }
        }
      }
      {
        name: 'Delete Source'
        type: 'Delete'
        dependsOn: [
          {
            activity: 'Convert File'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        policy: {
          timeout: '0.00:05:00'
          retry: 2
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          dataset: {
            referenceName: 'ingestion'
            type: 'DatasetReference'
            parameters: {
              fileName: {
                value: '@pipeline().parameters.fileName'
                type: 'Expression'
              }
              folderName: {
                value: '@pipeline().parameters.folderName'
                type: 'Expression'
              }
            }
          }
          enableLogging: false
          storeSettings: {
            type: 'AzureBlobFSReadSettings'
            recursive: true
            enablePartitionDiscovery: false
          }
        }
      }
    ]
    parameters: {
      fileName: {
        type: 'string'
      }
      folderName: {
        type: 'string'
      }
    }
    variables: {
      destinationFile: {
        type: 'String'
      }
      destinationFolder: {
        type: 'String'
      }
      folderArray: {
        type: 'Array'
      }
      folderCount: {
        type: 'Integer'
      }
      secondToLastFolder: {
        type: 'String'
      }
      thirdToLastFolder: {
        type: 'String'
      }
      fourthToLastFolder: {
        type: 'String'
      }
      scope: {
        type: 'String'
      }
      date: {
        type: 'String'
      }
      metric: {
        type: 'String'
      }
      detectedSchema: {
        type: 'String'
      }
      schemaMappings: {
        type: 'String'
      }
    }
  }
}

//------------------------------------------------------------------------------
// Start all triggers
//------------------------------------------------------------------------------

resource startTriggers 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${dataFactory.name}_startTriggers'
  // chinaeast2 is the only region in China that supports deployment scripts
  location: startsWith(location, 'china') ? 'chinaeast2' : location
  tags: union(tags, contains(tagsByResource, 'Microsoft.Resources/deploymentScripts') ? tagsByResource['Microsoft.Resources/deploymentScripts'] : {})
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  kind: 'AzurePowerShell'
  dependsOn: [
    identityRoleAssignments
    trigger_FileAdded
    trigger_SettingsUpdated
    trigger_DailySchedule
    trigger_MonthlySchedule
  ]
  properties: {
    azPowerShellVersion: '8.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    scriptContent: loadTextContent('./scripts/Start-Triggers.ps1')
    environmentVariables: [
      {
        name: 'DataFactorySubscriptionId'
        value: subscription().id
      }
      {
        name: 'DataFactoryResourceGroup'
        value: resourceGroup().name
      }
      {
        name: 'DataFactoryName'
        value: dataFactory.name
      }
      {
        name: 'Triggers'
        value: join(allHubTriggers, '|')
      }
    ]
  }
}

//==============================================================================
// Outputs
//==============================================================================

@description('The Resource ID of the Data factory.')
output resourceId string = dataFactory.id

@description('The Name of the Azure Data Factory instance.')
output name string = dataFactory.name
