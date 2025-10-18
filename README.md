# Hybrid User Sync - Azure Logic App

Deze oplossing automatiseert het synchroniseren van Entra ID gebruikers naar on-premises Active Directory Domain Services (AD DS) via API-driven provisioning en beheert de source of authority.

## Overzicht

De oplossing bestaat uit:
- **Main Logic App**: Verwerkt webhooks van Entra ID user updates
- **Renewal Logic App**: Beheert Graph API subscription renewal (elke 36 uur)
- **Key Vault**: Opslag voor subscription ID
- **Storage Account**: Dead letter queue voor gefaalde berichten
- **Log Analytics**: Centrale logging
- **Azure Monitor Alerts**: Monitoring en notificaties

## Workflow

### 1. Subscription Management
- De renewal Logic App draait elke 36 uur
- Controleert of er een subscription bestaat in Key Vault
- Vernieuwt bestaande subscription OF maakt nieuwe aan
- Slaat subscription ID op in Key Vault

### 2. User Update Processing
Wanneer een gebruiker wordt geüpdatet in Entra ID:

1. **Webhook trigger** → Main Logic App
2. **Admin Unit check**: Is gebruiker lid van opgegeven Admin Unit?
   - Nee → Stop processing
   - Ja → Ga verder
3. **Hybrid check**: Heeft gebruiker een `onPremisesImmutableId`?
   - Nee (cloud-only) → **Provision naar AD DS**
   - Ja (al hybrid) → **Set Source of Authority naar Entra**

### 3. Monitoring & Alerts
Alle events worden gelogd naar Log Analytics:
- `UserInAdminUnit` / `UserNotInAdminUnit`
- `ProvisioningStarted` / `ProvisioningSuccess`
- `SettingSourceOfAuthority` / `SourceOfAuthoritySuccess`
- `SubscriptionRenewalSuccess` / `SubscriptionRenewalFailure`
- `ProcessingError`

Alerts worden verzonden naar de action group bij:
- ✅ Succesvolle provisioning
- ✅ Succesvolle subscription renewal
- ❌ Processing errors
- ❌ Logic App failures
- ❌ Subscription renewal failures
- ⚠️ Geen renewal in 60 uur (heartbeat)

## Vereisten

### Azure Resources
- Azure subscription met Contributor rechten
- Resource Group

### Entra ID Permissions
De Managed Identity heeft de volgende Microsoft Graph API permissions nodig:

```powershell
# User.Read.All - Read user profiles
# AdministrativeUnit.Read.All - Read admin units
# Subscription.ReadWrite.All - Manage Graph subscriptions
# Directory.ReadWrite.All - Write directory data (source of authority)
```

### Provisioning Setup
Zorg ervoor dat API-driven provisioning is geconfigureerd volgens:
https://learn.microsoft.com/en-us/entra/identity/app-provisioning/inbound-provisioning-api-configure-app

## Deployment

### 1. Parameters aanpassen
Bewerk `main.parameters.json`:

```json
{
  "adminUnitId": {
    "value": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  "provisioningApiEndpoint": {
    "value": "https://graph.microsoft.com/v1.0/servicePrincipals/{id}/synchronization/jobs/{jobId}/bulkUpload"
  },
  "alertEmailAddresses": {
    "value": ["admin@yourdomain.com"]
  }
}
```

### 2. Deploy Bicep template

```powershell
# Login
Connect-AzAccount

# Selecteer subscription
Set-AzContext -Subscription "YOUR-SUBSCRIPTION-NAME"

# Deploy
New-AzResourceGroupDeployment `
  -ResourceGroupName "rg-hybriduser-dev" `
  -TemplateFile "main.bicep" `
  -TemplateParameterFile "main.parameters.json" `
  -Verbose
```

### 3. Permissions toekennen
Na deployment moet je de Managed Identity permissions geven in Entra ID:

```powershell
# Zie grant-permissions.ps1
```

### 4. Activeer Renewal Logic App
De renewal Logic App start automatisch na deployment. Controleer de eerste run in de Azure Portal.

## Deployment Script

```powershell
# deploy.ps1
./deploy.ps1 -ResourceGroupName "rg-hybriduser-dev" -Environment "dev"
```

## Post-Deployment

### Verificatie
1. Check of de renewal Logic App succesvol draait
2. Controleer Key Vault voor `graph-subscription-id` secret
3. Test de main Logic App webhook met een user update
4. Controleer Log Analytics voor events

### Troubleshooting
- **Dead Letter Queue**: `deadletter` container in storage account
- **Logs**: Log Analytics workspace → Logs → `HybridUserSync_CL`
- **Run History**: Logic Apps → Runs history

## Query Voorbeelden

### Alle events van de laatste 24 uur
```kql
HybridUserSync_CL
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

### Provisioning successen
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
| where EventType_s == "SubscriptionRenewalSuccess"
| project TimeGenerated, SubscriptionId_s, NewExpiration_s
```

## Architectuur

```
┌─────────────────┐
│   Entra ID      │
│   User Update   │
└────────┬────────┘
         │ webhook
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
│ (Every 36 hours)     │
│  ┌──────────────┐    │
│  │ 1. Get SubID │    │
│  │ 2. Renew/New │    │
│  │ 3. Store KV  │    │
│  └──────────────┘    │
└──────────────────────┘
```

## Kosten Indicatie
- Logic App: Pay-per-execution (~€0.000025/action)
- Storage: ~€0.02/GB
- Log Analytics: ~€2.30/GB ingested
- Key Vault: ~€0.03/10k operations

**Geschat**: €5-20/maand afhankelijk van volume.

## Support & Licentie
Intern project - Neem contact op met IT voor support.
