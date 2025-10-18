# Quick script to check Log Analytics logs
$query = @"
HybridUserSync_CL 
| where EventType_s == 'SubscriptionCreationSuccess' 
| order by TimeGenerated desc 
| take 1
| project TimeGenerated, EventType_s, SubscriptionId_s, ExpirationTime_s
"@

$body = @{
    query = $query
    timespan = "PT24H"
} | ConvertTo-Json

az rest --method POST `
    --uri "https://api.loganalytics.io/v1/workspaces/5bea7b42-edf8-45e0-8b33-405e3183e5b4/query" `
    --headers "Content-Type=application/json" `
    --body $body `
    --resource "https://api.loganalytics.io" `
    --query "tables[0].rows" -o json
