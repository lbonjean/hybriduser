# Test script for Hybrid User Sync Logic App
# This script sends a test webhook notification to the Logic App

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LogicAppCallbackUrl,
    
    [Parameter(Mandatory = $false)]
    [string]$UserId = "00000000-0000-0000-0000-000000000000",
    
    [Parameter(Mandatory = $false)]
    [switch]$ValidationTest
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Hybrid User Sync Logic App" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($ValidationTest) {
    Write-Host "Running validation test..." -ForegroundColor Yellow
    Write-Host ""
    
    # Send validation request
    $validationBody = @{
        validationToken = "test-validation-token-$(Get-Date -Format 'yyyyMMddHHmmss')"
    } | ConvertTo-Json
    
    try {
        $response = Invoke-WebRequest `
            -Uri $LogicAppCallbackUrl `
            -Method POST `
            -Body $validationBody `
            -ContentType "application/json" `
            -UseBasicParsing
        
        Write-Host "Response Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Response Body: $($response.Content)" -ForegroundColor White
        Write-Host ""
        Write-Host "✓ Validation test successful!" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Validation test failed: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Sending test user update notification..." -ForegroundColor Yellow
    Write-Host "User ID: $UserId" -ForegroundColor White
    Write-Host ""
    
    # Send user update notification
    $notificationBody = @{
        value = @(
            @{
                subscriptionId      = "test-subscription-id"
                clientState         = "HybridUserSync"
                expirationDateTime  = (Get-Date).AddDays(3).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                resource            = "users/$UserId"
                tenantId            = "test-tenant-id"
                resourceData        = @{
                    "@odata.type" = "microsoft.graph.user"
                    id            = $UserId
                }
            }
        )
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-WebRequest `
            -Uri $LogicAppCallbackUrl `
            -Method POST `
            -Body $notificationBody `
            -ContentType "application/json" `
            -UseBasicParsing
        
        Write-Host "Response Status: $($response.StatusCode)" -ForegroundColor Green
        Write-Host "Response Body:" -ForegroundColor White
        $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host ""
        Write-Host "✓ Test notification sent successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Check Log Analytics for processing results:" -ForegroundColor Yellow
        Write-Host "  Query: HybridUserSync_CL | where TimeGenerated > ago(5m)" -ForegroundColor White
    }
    catch {
        Write-Host "✗ Test failed: $_" -ForegroundColor Red
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response Body: $responseBody" -ForegroundColor Red
        }
        exit 1
    }
}

Write-Host ""
