# Monitoring Alerts Inschakelen

## Overzicht

De monitoring alerts worden **niet** automatisch gedeployed tijdens de initiële deployment. Dit is omdat de custom log tabel `HybridUserSync_CL` pas aangemaakt wordt nadat de eerste logs geschreven zijn. Azure valideert de alert queries tijdens deployment en faalt als de tabel nog niet bestaat.

## Wanneer Monitoring Inschakelen?

Schakel monitoring in **nadat**:
1. De Logic Apps zijn gedeployed
2. De renewal Logic App minimaal 1x succesvol is uitgevoerd
3. De main Logic App minimaal 1 user update heeft verwerkt
4. De custom log tabel `HybridUserSync_CL` bestaat in Log Analytics

## Stappen

### 1. Controleer of Custom Log Tabel Bestaat

```powershell
# Query Log Analytics om te verifiëren dat de tabel bestaat
$workspaceName = "log-hybriduser-dev"
$resourceGroup = "C0089-hybriduser-dev-rg"

# Via Azure Portal: Log Analytics Workspace → Logs → Run:
HybridUserSync_CL
| take 1
```

Als deze query succesvol is (ook al geeft hij geen resultaten), dan bestaat de tabel.

### 2. Deploy Monitoring Alerts

Update `main.parameters.json` om monitoring in te schakelen:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {
      "value": "dev"
    },
    "adminUnitId": {
      "value": "YOUR-ADMIN-UNIT-GUID"
    },
    "provisioningApiEndpoint": {
      "value": "https://your-api-endpoint.com/provision"
    },
    "alertEmailAddresses": {
      "value": ["admin@example.com"]
    },
    "deployMonitoring": {
      "value": true
    }
  }
}
```

**Let op:** Voeg de parameter `deployMonitoring` toe met waarde `true`.

### 3. Voer Deployment Opnieuw Uit

```powershell
.\deploy.ps1 -ResourceGroupName "C0089-hybriduser-dev-rg" -Environment "dev"
```

Dit deploy alleen de monitoring module - alle andere resources blijven ongewijzigd.

### 4. Schakel Alerts In

De alerts worden gedeployed in disabled state. Schakel ze handmatig in via Azure Portal:

1. Ga naar **Azure Monitor** → **Alerts** → **Alert rules**
2. Filter op resource group: `C0089-hybriduser-dev-rg`
3. Selecteer elke alert en klik **Enable**

Of via Azure CLI:

```powershell
# Lijst alle alert rules
az monitor scheduled-query list --resource-group "C0089-hybriduser-dev-rg" --output table

# Enable elke alert
$alerts = @(
    "alert-logic-hybriduser-dev-run-failures",
    "alert-logic-hybriduser-dev-processing-errors",
    "alert-logic-hybriduser-dev-provisioning-success",
    "alert-logic-hybriduser-dev-renewal-success",
    "alert-logic-hybriduser-dev-renewal-failure",
    "alert-logic-hybriduser-dev-no-renewal-heartbeat",
    "alert-logic-hybriduser-dev-soa-success"
)

foreach ($alert in $alerts) {
    az monitor scheduled-query update `
        --name $alert `
        --resource-group "C0089-hybriduser-dev-rg" `
        --enabled true
}
```

## Alert Overzicht

Na inschakelen heb je de volgende alerts:

| Alert Naam | Severity | Beschrijving | Evaluatie |
|-----------|----------|--------------|-----------|
| Logic App Run Failures | Critical (1) | Logic App run is mislukt | Elke 5 min |
| User Processing Errors | Warning (2) | Fout bij user processing | Elke 5 min |
| Successful Provisioning | Info (3) | User succesvol geprovisioned naar AD DS | Elke 15 min |
| Subscription Renewal Success | Info (3) | Graph subscription succesvol vernieuwd | Elke 15 min |
| Subscription Renewal Failure | Critical (1) | Subscription renewal gefaald | Elke 5 min |
| No Renewal Heartbeat | Critical (1) | Geen renewal in laatste 48 uur | Elk uur |
| Source of Authority Success | Info (3) | Source of authority succesvol gewijzigd | Elke 15 min |

## Troubleshooting

### "Table HybridUserSync_CL does not exist"

De tabel bestaat nog niet. Zorg ervoor dat:
1. De Logic Apps draaien en logs schrijven
2. Wacht 10-15 minuten na de eerste log entry (custom tables hebben enige vertraging)
3. Controleer diagnostic settings op beide Logic Apps

### Alert Wordt Niet Getriggerd

1. Controleer of de alert **enabled** is in Azure Portal
2. Verifieer dat er data in de tabel staat:
   ```kusto
   HybridUserSync_CL
   | where TimeGenerated > ago(1h)
   | order by TimeGenerated desc
   ```
3. Test de query handmatig in Log Analytics
4. Check de action group configuratie

### Te Veel Alert Emails

Voor **info** alerts (severity 3) kun je de evaluatiefrequentie verhogen of de alerts uitschakelen als je ze niet nodig hebt. Warning en critical alerts zijn essentieel voor monitoring.

## Best Practices

1. **Start met critical alerts**: Enable eerst alleen severity 1 alerts
2. **Test alerts**: Trigger een error om te verifiëren dat alerts werken
3. **Tune thresholds**: Pas drempelwaarden aan op basis van je omgeving
4. **Action groups**: Configureer verschillende action groups voor verschillende severity levels
5. **Heartbeat monitoring**: De "No Renewal Heartbeat" alert is cruciaal - deze moet altijd enabled zijn

## Zie Ook

- [QUICKSTART.md](QUICKSTART.md) - Initiële deployment instructies
- [README.md](README.md) - Volledige documentatie
- [query-logs.ps1](query-logs.ps1) - Script om logs te queryen
