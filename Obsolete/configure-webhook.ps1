# Post-Deployment Configuration Script
# This script configures the webhook callback URL in the renewal Logic App

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "deployment-outputs-dev.json"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Post-Deployment Configuration" -ForegroundColor Cyan
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
$renewalLogicAppName = $outputs.renewalLogicAppName.value
$keyVaultName = $outputs.keyVaultName.value

Write-Host "  Main Logic App: $mainLogicAppName" -ForegroundColor White
Write-Host "  Renewal Logic App: $renewalLogicAppName" -ForegroundColor White
Write-Host "  Key Vault: $keyVaultName" -ForegroundColor White
Write-Host ""

# Get main Logic App callback URL
Write-Host "Retrieving webhook callback URL..." -ForegroundColor Yellow
try {
    $mainLogicApp = Get-AzLogicApp `
        -ResourceGroupName $ResourceGroupName `
        -Name $mainLogicAppName
    
    $callbackUrl = Get-AzLogicAppTriggerCallbackUrl `
        -ResourceGroupName $ResourceGroupName `
        -Name $mainLogicAppName `
        -TriggerName "manual"

    Write-Host "✓ Callback URL retrieved: $($callbackUrl.Value)" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to retrieve callback URL: $_" -ForegroundColor Red
    exit 1
}

# Update renewal Logic App parameter
Write-Host ""
Write-Host "Updating renewal Logic App configuration..." -ForegroundColor Yellow
try {
    # Get the current workflow definition
    $workflow = Get-AzResource `
        -ResourceGroupName $ResourceGroupName `
        -ResourceType "Microsoft.Logic/workflows" `
        -Name $renewalLogicAppName `
        -ApiVersion "2019-05-01"
    
    # Check if parameters exist
    if (-not $workflow.Properties.parameters) {
        $workflow.Properties.parameters = @{}
    }
    
    # Update the webhookCallbackUrl parameter
    if (-not $workflow.Properties.parameters.webhookCallbackUrl) {
        $workflow.Properties.parameters | Add-Member -NotePropertyName "webhookCallbackUrl" -NotePropertyValue @{
            type  = "String"
            value = $callbackUrl.Value
        }
    }
    else {
        $workflow.Properties.parameters.webhookCallbackUrl.value = $callbackUrl.Value
    }
    
    # Update the workflow using REST API
    $null = Set-AzResource `
        -ResourceId $workflow.ResourceId `
        -Properties $workflow.Properties `
        -ApiVersion "2019-05-01" `
        -Force
    
    Write-Host "✓ Renewal Logic App updated" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to update renewal Logic App: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual update required:" -ForegroundColor Yellow
    Write-Host "1. Go to Azure Portal → Logic Apps → $renewalLogicAppName" -ForegroundColor White
    Write-Host "2. Open Logic App designer" -ForegroundColor White
    Write-Host "3. Find the 'Create_new_subscription' HTTP action" -ForegroundColor White
    Write-Host "4. Update the notificationUrl in the body to:" -ForegroundColor White
    Write-Host "   $($callbackUrl.Value)" -ForegroundColor Cyan
    Write-Host ""
    # Don't exit - continue with Key Vault storage
}

# Optionally store callback URL in Key Vault for reference
Write-Host ""
Write-Host "Storing callback URL in Key Vault (optional)..." -ForegroundColor Yellow
try {
    $secretValue = ConvertTo-SecureString -String $callbackUrl.Value -AsPlainText -Force
    Set-AzKeyVaultSecret `
        -VaultName $keyVaultName `
        -Name "webhook-callback-url" `
        -SecretValue $secretValue `
        -ContentType "text/plain" | Out-Null
    
    Write-Host "✓ Callback URL stored in Key Vault" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Failed to store in Key Vault (non-critical): $_" -ForegroundColor Yellow
}

# Trigger the renewal Logic App to create initial subscription
Write-Host ""
Write-Host "Triggering initial subscription creation..." -ForegroundColor Yellow
$confirm = Read-Host "Do you want to trigger the renewal Logic App now to create the subscription? (yes/no)"
if ($confirm -eq "yes") {
    try {
        Start-AzLogicApp `
            -ResourceGroupName $ResourceGroupName `
            -Name $renewalLogicAppName `
            -TriggerName "Recurrence" | Out-Null
        
        Write-Host "✓ Renewal Logic App triggered" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Monitor the run in Azure Portal or check logs in 1-2 minutes" -ForegroundColor Gray
    }
    catch {
        Write-Host "⚠ Failed to trigger Logic App: $_" -ForegroundColor Yellow
        Write-Host "  You can manually trigger it from the Azure Portal" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ Webhook callback URL configured" -ForegroundColor Green
Write-Host "✓ Ready to receive Entra ID notifications" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 1-2 minutes for subscription creation" -ForegroundColor White
Write-Host "  2. Verify subscription ID in Key Vault: $keyVaultName" -ForegroundColor White
Write-Host "  3. Test with: .\test-logicapp.ps1 -LogicAppCallbackUrl '<URL>'" -ForegroundColor White
Write-Host ""
