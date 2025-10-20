# Configure Log Analytics API Connections
# This script automatically configures the Log Analytics Data Collector connections

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName = "log-hybriduser-dev"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configure Log Analytics Connections" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get Workspace credentials
Write-Host "Retrieving Log Analytics credentials..." -ForegroundColor Yellow
try {
    $workspace = Get-AzOperationalInsightsWorkspace `
        -ResourceGroupName $ResourceGroupName `
        -Name $WorkspaceName `
        -ErrorAction Stop
    
    $keys = Get-AzOperationalInsightsWorkspaceSharedKeys `
        -ResourceGroupName $ResourceGroupName `
        -Name $WorkspaceName `
        -ErrorAction Stop
    
    $workspaceId = $workspace.CustomerId.ToString()
    $workspaceKey = $keys.PrimarySharedKey
    
    Write-Host "✓ Workspace ID: $workspaceId" -ForegroundColor Green
    Write-Host "✓ Primary Key: $($workspaceKey.Substring(0, 20))..." -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to retrieve workspace credentials: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get subscription ID
$subscriptionId = (Get-AzContext).Subscription.Id

# Connection names
$connections = @(
    "azureloganalyticsdatacollector-logic-hybriduser-dev",
    "azureloganalyticsdatacollector-logic-hybriduser-dev-renewal"
)

foreach ($connectionName in $connections) {
    Write-Host "Configuring connection: $connectionName..." -ForegroundColor Yellow
    
    try {
        # Get current connection
        $connectionResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/$connectionName"
        
        # Build the connection properties
        $connectionProperties = @{
            api = @{
                id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/westeurope/managedApis/azureloganalyticsdatacollector"
            }
            displayName = $connectionName
            parameterValues = @{
                username = $workspaceId
                password = $workspaceKey
            }
        }
        
        # Update the connection using REST API
        $body = @{
            properties = $connectionProperties
            location = "westeurope"
        } | ConvertTo-Json -Depth 10
        
        $uri = "https://management.azure.com$connectionResourceId`?api-version=2016-06-01"
        
        $response = Invoke-AzRestMethod `
            -Method PUT `
            -Uri $uri `
            -Payload $body
        
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
            Write-Host "  ✓ Connection configured" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Failed: HTTP $($response.StatusCode)" -ForegroundColor Red
            Write-Host "  Response: $($response.Content)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ✗ Failed to configure connection: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: Trigger the renewal Logic App to test" -ForegroundColor Yellow
Write-Host "  az rest --method POST --uri `"/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/logic-hybriduser-dev-renewal/triggers/Recurrence/run?api-version=2019-05-01`"" -ForegroundColor Gray
Write-Host ""
