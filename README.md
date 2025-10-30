# Hybrid User Sync - Azure Logic App

Automates synchronization of Entra ID users to on-premises Active Directory via API-driven provisioning and manages source of authority.

## Overview

This solution consists of:
- **Main Logic App**: Processes webhooks for Entra ID user updates
- **Renewal Logic App**: Manages Graph API subscription renewal (every 12 hours)
- **Key Vault**: Stores subscription ID
- **Storage Account**: Dead letter queue for failed messages
- **Log Analytics**: Centralized logging
- **Azure Monitor Alerts**: Monitoring and notifications

## Workflow

### 1. Subscription Management
- Renewal Logic App runs every 12 hours
- Checks if subscription exists in Key Vault
- Renews existing subscription OR creates new one
- Stores subscription ID in Key Vault

### 2. User Update Processing
When a user is updated in Entra ID:

1. **Webhook trigger** → Main Logic App
2. **Admin Unit check**: Is user member of specified Administrative Unit?
   - No → Stop processing
   - Yes → Continue
3. **Hybrid check**: Does user have `onPremisesImmutableId`?
   - No (cloud-only) → **Provision to on-premises AD**
   - Yes (already hybrid) → **Set Source of Authority to Entra**

### 3. Monitoring & Alerts
All events are logged to Log Analytics:
- `UserInAdminUnit` / `UserNotInAdminUnit`
- `ProvisioningStarted` / `ProvisioningSuccess`
- `SettingSourceOfAuthority` / `SourceOfAuthoritySuccess`
- `SubscriptionRenewalSuccess` / `SubscriptionRenewalFailure`
- `ProcessingError`

Alerts are sent to action group for:
- ✅ Successful provisioning
- ✅ Successful subscription renewal
- ❌ Processing errors
- ❌ Logic App failures
- ❌ Subscription renewal failures
- ⚠️ No renewal in 60 hours (heartbeat)

## Prerequisites

### Azure Resources
- Azure subscription with Contributor permissions
- Resource Group

### Entra ID Setup

#### 1. Administrative Unit
Create an Administrative Unit in Entra ID and add users that should be provisioned to on-premises AD.

```powershell
# Get Admin Unit ID
Connect-MgGraph -Scopes "AdministrativeUnit.Read.All"
Get-MgDirectoryAdministrativeUnit | Select-Object DisplayName, Id
```

#### 2. API-driven Provisioning App
Configure the enterprise app "API-driven provisioning to on-premises Active Directory" from the Entra app gallery:

Follow: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/inbound-provisioning-api-configure-app

**Retrieve the provisioning endpoint URL** from the app configuration after setup.

#### 3. Passwordless Authentication
**CRITICAL**: Hybrid users must have passwordless authentication (Windows Hello for Business or FIDO2) configured before provisioning. This solution sets Entra as source of authority, requiring passwordless sign-in methods.

### Graph API Permissions
The Logic Apps' Managed Identities require these Microsoft Graph API permissions (granted via `grant-system-identity-permissions.ps1`):

- `User.Read.All` - Read user profiles
- `AdministrativeUnit.Read.All` - Read administrative units
- `Directory.ReadWrite.All` - Write directory data (source of authority)

## Deployment

### Quick Install

```powershell
# Example usage
./install-hybriduser.ps1 `
  -resourceGroup "C0089-hybriduser-rg" `
  -namePrefix "C0089" `
  -location "northeurope" `
  -adminUnitId "1d1c8021-04ab-4015-a2b7-5aa5d8599b4d" `
  -provisioningApiEndpoint "https://graph.microsoft.com/v1.0/servicePrincipals/{servicePrincipalId}/synchronization/jobs/{jobId}/bulkUpload"
```

**What it does:**
1. Creates resource group
2. Deploys Bicep templates (Logic Apps, Key Vault, Storage, Log Analytics)
3. Grants Microsoft Graph permissions to both Logic App Managed Identities

**Parameters:**
- `resourceGroup`: Azure resource group name
- `namePrefix`: Customer-specific prefix for resource naming
- `location`: Azure region (e.g., `northeurope`, `westeurope`)
- `adminUnitId`: GUID of the Entra Administrative Unit
- `provisioningApiEndpoint`: API-driven provisioning bulk upload endpoint URL

## Post-Deployment Verification

### 1. Check Renewal Logic App
```powershell
# Check run history
az logicapp show --name "<namePrefix>-hybriduser-renewal-logic" --resource-group "<resourceGroup>"
```

Or via Azure Portal:
- Navigate to Logic Apps → `<namePrefix>-hybriduser-renewal-logic`
- Check "Runs history" - first run should succeed
- Verify Key Vault → Secrets → `graph-subscription-id` exists

### 2. Test Main Logic App
Add a test user to the Administrative Unit and update their profile. Check Log Analytics for processing events.

### 3. Enable Monitoring (Optional)
After the custom log table is created (after first Logic App run):

```powershell
# Redeploy with monitoring enabled
./install-hybriduser.ps1 <parameters> -deployMonitoring $true
```

## Troubleshooting

### Dead Letter Queue
Failed messages are stored in: Storage Account → Containers → `deadletter`

### Logs
Log Analytics workspace → Logs → Query: `HybridUserSync_CL`

### Run History
Azure Portal → Logic Apps → Runs history

## Log Analytics Queries

### All events (last 24 hours)
```kql
HybridUserSync_CL
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

### Provisioning successes
```kql
HybridUserSync_CL
| where EventType_s == "ProvisioningSuccess"
| project TimeGenerated, UserPrincipalName_s, UserId_s
```

### Errors
```kql
HybridUserSync_CL
| where EventType_s == "ProcessingError"
| project TimeGenerated, UserId_s, Error_s
```

### Subscription renewals
```kql
HybridUserSync_CL
| where EventType_s in ("SubscriptionRenewalSuccess", "SubscriptionRenewalFailure")
| project TimeGenerated, EventType_s, SubscriptionId_s, NewExpiration_s
```

## Architecture

```
┌─────────────────┐
│   Entra ID      │
│   User Update   │
└────────┬────────┘
         │ webhook (12h renewal)
         ▼
┌─────────────────────────┐
│  Main Logic App         │
│  ┌──────────────────┐   │
│  │ 1. Validate      │   │
│  │ 2. Check AdminU  │   │
│  │ 3. Check Hybrid  │   │
│  │ 4a. Provision OR │   │
│  │ 4b. Set SoA      │   │
│  └──────────────────┘   │
└───┬─────────────┬───────┘
    │             │
    │ error       │ success
    ▼             ▼
┌─────────┐   ┌──────────────┐
│  Dead   │   │ Log Analytics│
│ Letter  │   │   + Alerts   │
└─────────┘   └──────────────┘

┌──────────────────────┐
│ Renewal Logic App    │
│ (Every 12 hours)     │
│  ┌──────────────┐    │
│  │ 1. Get SubID │    │
│  │ 2. Renew/New │    │
│  │ 3. Store KV  │    │
│  └──────────────┘    │
└──────────────────────┘
```

## Estimated Costs
- Logic Apps: Pay-per-execution (~€0.000025/action)
- Storage: ~€0.02/GB
- Log Analytics: ~€2.30/GB ingested
- Key Vault: ~€0.03/10k operations

**Estimated total**: €5-20/month depending on volume

## Support
Internal project - Contact IT for support
