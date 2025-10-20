# Test script voor webhook notifications
# Simuleert een Microsoft Graph change notification

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserId = "test-user-id-12345",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "deployment-outputs-dev.json"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Webhook Notification Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if output file exists
if (-not (Test-Path $OutputFile)) {
    Write-Host "✗ Output file not found: $OutputFile" -ForegroundColor Red
    Write-Host "  Please run deploy.ps1 first" -ForegroundColor Yellow
    exit 1
}

# Load deployment outputs
Write-Host "Loading deployment outputs..." -ForegroundColor Yellow
$outputs = Get-Content $OutputFile | ConvertFrom-Json
$mainLogicAppName = $outputs.logicAppName.value
$resourceGroupName = ($outputs.logicAppName.value -split '-')[1..2] -join '-' + '-rg'

# Get webhook URL
Write-Host "Retrieving webhook URL..." -ForegroundColor Yellow
try {
    $callbackUrl = Get-AzLogicAppTriggerCallbackUrl `
        -ResourceGroupName "C0089-hybriduser-dev-rg" `
        -Name $mainLogicAppName `
        -TriggerName "manual"
    
    Write-Host "✓ Webhook URL retrieved" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to retrieve webhook URL: $_" -ForegroundColor Red
    exit 1
}

# Create test notification payload
$notification = @{
    value = @(
        @{
            subscriptionId = "83554537-3884-4900-ac02-b3c3426d2d1e"
            clientState = "HybridUserSync"
            changeType = "updated"
            resource = "users/$UserId"
            subscriptionExpirationDateTime = (Get-Date).AddHours(70).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
            resourceData = @{
                "@odata.type" = "#Microsoft.Graph.User"
                "@odata.id" = "users/$UserId"
                id = $UserId
            }
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "Test Notification Payload:" -ForegroundColor Yellow
Write-Host $notification -ForegroundColor Gray
Write-Host ""

# Send test notification
Write-Host "Sending test notification to webhook..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod `
        -Uri $callbackUrl.Value `
        -Method Post `
        -Body $notification `
        -ContentType "application/json" `
        -ErrorAction Stop
    
    Write-Host "✓ Notification sent successfully" -ForegroundColor Green
    
    if ($response) {
        Write-Host ""
        Write-Host "Response:" -ForegroundColor Yellow
        Write-Host ($response | ConvertTo-Json) -ForegroundColor Gray
    }
}
catch {
    if ($_.Exception.Response.StatusCode -eq 202) {
        Write-Host "✓ Notification accepted (HTTP 202)" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Failed to send notification: $_" -ForegroundColor Red
        Write-Host "  Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitor Logic App execution:" -ForegroundColor Yellow
Write-Host "  1. Azure Portal → Logic Apps → $mainLogicAppName → Runs" -ForegroundColor White
Write-Host "  2. Check Log Analytics for processing logs:" -ForegroundColor White
Write-Host "     HybridUserSync_CL | where UserId_s == '$UserId' | order by TimeGenerated desc" -ForegroundColor Gray
Write-Host ""
Write-Host "To test with a real user:" -ForegroundColor Yellow
Write-Host "  1. Make a change to a user in the admin unit" -ForegroundColor White
Write-Host "  2. Wait a few seconds for Graph to send notification" -ForegroundColor White
Write-Host "  3. Check Logic App runs and Log Analytics" -ForegroundColor White
Write-Host ""
