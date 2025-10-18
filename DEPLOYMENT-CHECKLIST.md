# Deployment Checklist

## Pre-Deployment

### Vereisten
- [ ] Azure subscription met Contributor rechten
- [ ] Global Administrator of Privileged Role Administrator rechten in Entra ID
- [ ] PowerShell 7+ geïnstalleerd
- [ ] Azure PowerShell module (`Az`) geïnstalleerd
- [ ] Microsoft Graph PowerShell module geïnstalleerd

```powershell
# Installeer vereiste modules
Install-Module Az -Scope CurrentUser -Force
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

### API-driven Provisioning Setup
- [ ] API-driven provisioning is geconfigureerd volgens Microsoft docs
- [ ] Service Principal is aangemaakt
- [ ] Synchronization job is actief
- [ ] Provisioning endpoint URL is bekend
- [ ] Test provisioning is succesvol uitgevoerd

**Documentatie**: https://learn.microsoft.com/en-us/entra/identity/app-provisioning/inbound-provisioning-api-configure-app

### Administrative Unit
- [ ] Administrative Unit is aangemaakt in Entra ID
- [ ] Test users zijn toegevoegd aan de Admin Unit
- [ ] Admin Unit GUID is bekend

```powershell
# Vind Admin Unit ID
Connect-MgGraph -Scopes "AdministrativeUnit.Read.All"
Get-MgDirectoryAdministrativeUnit | Select-Object DisplayName, Id
```

## Deployment

### Stap 1: Parameters configureren
- [ ] `main.parameters.json` is gekopieerd en aangepast
- [ ] `adminUnitId` is ingevuld met correcte GUID
- [ ] `provisioningApiEndpoint` is ingevuld met correcte URL
- [ ] `alertEmailAddresses` bevat juiste email adressen
- [ ] `location` is ingesteld (default: westeurope)
- [ ] `environmentName` is ingesteld (dev/test/prod)

### Stap 2: Azure Deployment
```powershell
# Login
Connect-AzAccount
Set-AzContext -Subscription "Your-Subscription-Name"

# Deploy
.\deploy.ps1 -ResourceGroupName "rg-hybriduser-dev" -Environment "dev"
```

- [ ] Deployment is succesvol afgerond
- [ ] Deployment outputs zijn opgeslagen
- [ ] Alle resources zijn aangemaakt in resource group

**Verwachte resources**:
- 2x Logic App (main + renewal)
- 1x Key Vault
- 1x Storage Account (dead letter)
- 1x Log Analytics Workspace
- 1x Action Group
- 1x Managed Identity
- 7x Metric Alert

### Stap 3: Permissions
```powershell
.\grant-permissions.ps1 -PrincipalId "managed-identity-principal-id"
```

- [ ] Permissions zijn succesvol toegekend
- [ ] Geen errors in de output
- [ ] Permissions zijn zichtbaar in Entra ID

**Verifieer in Azure Portal**:
- Entra ID → Enterprise Applications → Zoek Managed Identity → Permissions

### Stap 4: Webhook configuratie
```powershell
.\configure-webhook.ps1 -ResourceGroupName "rg-hybriduser-dev"
```

- [ ] Callback URL is opgehaald
- [ ] Renewal Logic App is updated
- [ ] Callback URL is opgeslagen in Key Vault (optioneel)
- [ ] Eerste trigger is uitgevoerd

## Post-Deployment Verificatie

### Renewal Logic App
- [ ] Renewal Logic App heeft gedraaid (check runs history)
- [ ] Run was succesvol (status: Succeeded)
- [ ] Geen errors in de run details

**Azure Portal**: Logic Apps → logic-hybriduser-{env}-renewal → Runs history

### Graph Subscription
- [ ] Key Vault bevat secret `graph-subscription-id`
- [ ] Secret value is een valid GUID
- [ ] Log Analytics bevat `SubscriptionRenewalSuccess` event

```kql
HybridUserSync_CL
| where EventType_s == "SubscriptionRenewalSuccess"
| order by TimeGenerated desc
| take 1
```

### Monitoring Setup
- [ ] Log Analytics workspace is actief
- [ ] Metric alerts zijn enabled
- [ ] Action group bevat correcte email adressen
- [ ] Test alert email ontvangen

**Test alert**:
Azure Portal → Monitor → Alerts → Create test alert

## Testing

### Test 1: Validation Webhook
```powershell
$callbackUrl = Get-AzLogicAppTriggerCallbackUrl `
    -ResourceGroupName "rg-hybriduser-dev" `
    -Name "logic-hybriduser-dev" `
    -TriggerName "manual"

.\test-logicapp.ps1 -LogicAppCallbackUrl $callbackUrl.Value -ValidationTest
```

- [ ] HTTP 200 response ontvangen
- [ ] Validation token terug ontvangen in response

### Test 2: User Update (Simulated)
```powershell
.\test-logicapp.ps1 -LogicAppCallbackUrl $callbackUrl.Value -UserId "test-guid"
```

- [ ] HTTP 202 response ontvangen
- [ ] Logic App run is zichtbaar in runs history
- [ ] Events zijn zichtbaar in Log Analytics

### Test 3: Real User Update
- [ ] Test user is lid van Admin Unit
- [ ] Test user is cloud-only (geen immutableId)
- [ ] Wijziging maken aan test user (bijv. update displayName)
- [ ] Webhook wordt getriggerd
- [ ] User wordt geprocessed
- [ ] Events zijn zichtbaar in logs

```kql
HybridUserSync_CL
| where UserPrincipalName_s == "testuser@domain.com"
| order by TimeGenerated desc
```

### Test 4: Error Handling
- [ ] Test met invalid user ID
- [ ] Error wordt gelogd
- [ ] Dead letter queue bevat error details
- [ ] Alert email wordt ontvangen

## Monitoring Verification

### Log Analytics Queries
- [ ] `HybridUserSync_CL` table exists
- [ ] Events zijn zichtbaar
- [ ] Alle event types zijn getest

```powershell
.\query-logs.ps1 -WorkspaceId "workspace-id" -QueryType "Summary"
```

### Alerts
- [ ] Alert voor Processing Errors werkt
- [ ] Alert voor Provisioning Success werkt
- [ ] Alert voor Renewal Success werkt
- [ ] Alert voor Renewal Failure werkt
- [ ] Heartbeat alert (60h) is geconfigureerd

## Documentation

- [ ] README.md is gelezen
- [ ] QUICKSTART.md is gelezen
- [ ] ARCHITECTURE.md is bekeken
- [ ] Team is geïnformeerd over nieuwe oplossing
- [ ] Runbook is aangemaakt voor troubleshooting
- [ ] Contactpersonen zijn gedocumenteerd

## Rollback Plan

Als deployment niet werkt:

```powershell
# Verwijder resource group
Remove-AzResourceGroup -Name "rg-hybriduser-dev" -Force

# Verwijder app role assignments
Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId "principal-id" -AppRoleAssignmentId "assignment-id"
```

- [ ] Rollback procedure is getest
- [ ] Backup van oude configuratie (indien van toepassing)

## Production Readiness

Voordat je naar productie gaat:

- [ ] Alle tests zijn succesvol in DEV
- [ ] Monitoring is > 1 week actief in DEV
- [ ] Geen kritieke errors in DEV
- [ ] Performance is acceptabel
- [ ] Kosten zijn binnen budget
- [ ] Security review is uitgevoerd
- [ ] Change management proces is gevolgd
- [ ] Rollback plan is getest
- [ ] Team training is gegeven
- [ ] On-call procedure is gedefinieerd

### Production Differences
- [ ] `environmentName` = "prod"
- [ ] Production Admin Unit is gebruikt
- [ ] Production alerting email addresses
- [ ] Production provisioning endpoint
- [ ] Verhoogde retention voor logs (bijv. 365 dagen)

## Sign-off

| Rol | Naam | Datum | Handtekening |
|-----|------|-------|--------------|
| Deployer | | | |
| Reviewer | | | |
| Security | | | |
| Manager | | | |

## Notes

<!-- Add any deployment-specific notes here -->
