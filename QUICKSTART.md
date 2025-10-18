# Hybrid User Sync - Quick Start Guide

## Overzicht
Deze oplossing automatiseert het synchroniseren van Entra ID gebruikers naar on-premises Active Directory via API-driven provisioning.

## Snelle Start (5 stappen)

### Stap 1: Parameters configureren
Bewerk `main.parameters.json`:

```json
{
  "adminUnitId": {
    "value": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  // Jouw Admin Unit GUID
  },
  "provisioningApiEndpoint": {
    "value": "https://graph.microsoft.com/v1.0/servicePrincipals/{id}/synchronization/jobs/{jobId}/bulkUpload"
  },
  "alertEmailAddresses": {
    "value": ["admin@joudomein.nl", "team@joudomein.nl"]
  }
}
```

#### Admin Unit ID vinden:
```powershell
Connect-MgGraph -Scopes "AdministrativeUnit.Read.All"
Get-MgDirectoryAdministrativeUnit | Select-Object DisplayName, Id
```

#### Provisioning API Endpoint vinden:
Zie: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/inbound-provisioning-api-configure-app

### Stap 2: Deployen
```powershell
# Login naar Azure
Connect-AzAccount

# Selecteer subscription
Set-AzContext -Subscription "Jouw Subscription Name"

# Deploy
.\deploy.ps1 -ResourceGroupName "rg-hybriduser-dev" -Environment "dev"
```

**Duur**: ~5-10 minuten

### Stap 3: Permissions toekennen
```powershell
# Gebruik de Principal ID uit de deployment output
.\grant-permissions.ps1 -PrincipalId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Vereiste rechten**: Global Administrator of Privileged Role Administrator

**Permissions die worden toegekend**:
- `User.Read.All` - Gebruikers lezen
- `AdministrativeUnit.Read.All` - Admin units lezen  
- `Subscription.Read.All` - Graph subscriptions beheren
- `Directory.ReadWrite.All` - Source of Authority aanpassen

### Stap 4: Webhook configureren
```powershell
.\configure-webhook.ps1 -ResourceGroupName "rg-hybriduser-dev"
```

Dit script:
- Haalt de callback URL op van de main Logic App
- Configureert deze in de renewal Logic App
- Triggert de eerste subscription aanmaak

### Stap 5: Verifiëren
```powershell
# Check logs
.\query-logs.ps1 -WorkspaceId "<workspace-id>" -QueryType "Summary"

# Check heartbeat
.\query-logs.ps1 -WorkspaceId "<workspace-id>" -QueryType "Heartbeat"
```

Of in Azure Portal:
1. Ga naar Logic Apps → `logic-hybriduser-dev-renewal`
2. Check "Runs history" - laatste run moet succesvol zijn
3. Ga naar Key Vault → Secrets → `graph-subscription-id` moet bestaan

## Testen

### Test 1: Validation webhook
```powershell
# Haal callback URL op
$callbackUrl = Get-AzLogicAppTriggerCallbackUrl `
    -ResourceGroupName "rg-hybriduser-dev" `
    -Name "logic-hybriduser-dev" `
    -TriggerName "manual"

# Test
.\test-logicapp.ps1 -LogicAppCallbackUrl $callbackUrl.Value -ValidationTest
```

### Test 2: User update notification
```powershell
.\test-logicapp.ps1 -LogicAppCallbackUrl $callbackUrl.Value -UserId "test-user-guid"
```

**Let op**: Deze test stuurt een fake notification. Voor echte testing, maak een wijziging aan een test user in de Admin Unit.

## Monitoring

### Log Queries (Log Analytics)

**Alle events laatste 24u**:
```kql
HybridUserSync_CL
| where TimeGenerated > ago(24h)
| order by TimeGenerated desc
```

**Provisioning successen**:
```kql
HybridUserSync_CL
| where EventType_s == "ProvisioningSuccess"
| project TimeGenerated, UserPrincipalName_s, UserId_s
```

**Errors**:
```kql
HybridUserSync_CL
| where EventType_s == "ProcessingError"
| project TimeGenerated, UserId_s, Error_s
```

**Subscription renewals**:
```kql
HybridUserSync_CL
| where EventType_s in ("SubscriptionRenewalSuccess", "SubscriptionRenewalFailure")
| project TimeGenerated, EventType_s, SubscriptionId_s
```

### Alerts
Je ontvangt automatisch emails bij:
- ✅ Succesvolle user provisioning
- ✅ Succesvolle subscription renewal
- ❌ Processing errors
- ❌ Logic App failures
- ❌ Subscription renewal failures
- ⚠️ Geen renewal in 60 uur

## Troubleshooting

### Probleem: Subscription wordt niet aangemaakt

**Check**:
1. Permissions zijn correct toegekend?
   ```powershell
   Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId "<principal-id>"
   ```

2. Renewal Logic App logs:
   ```
   Azure Portal → Logic Apps → logic-hybriduser-dev-renewal → Runs history
   ```

3. Error in logs:
   ```kql
   HybridUserSync_CL
   | where EventType_s == "SubscriptionRenewalFailure"
   ```

### Probleem: Users worden niet geprocessed

**Check**:
1. Is de user lid van de Admin Unit?
   ```powershell
   Get-MgDirectoryAdministrativeUnitMember -AdministrativeUnitId "<admin-unit-id>"
   ```

2. Main Logic App runs:
   ```
   Azure Portal → Logic Apps → logic-hybriduser-dev → Runs history
   ```

3. Dead letter queue:
   ```
   Azure Portal → Storage Account → Containers → deadletter
   ```

### Probleem: Provisioning API errors

**Check**:
1. Is API-driven provisioning correct geconfigureerd?
   - Service Principal bestaat?
   - Synchronization job is actief?
   - Endpoint URL is correct?

2. Test provisioning API handmatig:
   ```powershell
   $token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
   Invoke-RestMethod `
       -Uri "<provisioning-endpoint>" `
       -Method POST `
       -Headers @{Authorization = "Bearer $token"} `
       -Body '<test payload>' `
       -ContentType "application/json"
   ```

## Kosten

**Geschatte maandelijkse kosten** (dev environment):
- Logic Apps: €5-10 (afhankelijk van volume)
- Storage: €0.50
- Log Analytics: €2-5
- Key Vault: €0.50
- **Totaal**: ~€10-20/maand

**Productie** (500 users/dag):
- €20-40/maand

## Support

Voor vragen of problemen:
1. Check de logs in Log Analytics
2. Check dead letter queue voor gefaalde berichten
3. Neem contact op met IT

## Handige Links

- [API-driven provisioning setup](https://learn.microsoft.com/en-us/entra/identity/app-provisioning/inbound-provisioning-api-configure-app)
- [Source of Authority docs](https://learn.microsoft.com/en-us/entra/identity/hybrid/user-source-of-authority-overview)
- [Graph API subscriptions](https://learn.microsoft.com/en-us/graph/webhooks)
- [Logic Apps monitoring](https://learn.microsoft.com/en-us/azure/logic-apps/monitor-logic-apps)
