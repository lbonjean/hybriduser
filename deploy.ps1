# Hybrid User Sync - Deployment Script
# This script deploys the complete solution to Azure

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = "main.parameters.json"
)

# Error handling
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Hybrid User Sync - Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
Write-Host "Checking Azure connection..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if (-not $context) {
        throw "Not logged in"
    }
    Write-Host "✓ Connected to subscription: $($context.Subscription.Name)" -ForegroundColor Green
}
catch {
    Write-Host "✗ Not logged in to Azure. Please run Connect-AzAccount" -ForegroundColor Red
    exit 1
}

# Check if resource group exists, create if not
Write-Host ""
Write-Host "Checking resource group..." -ForegroundColor Yellow
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group: $ResourceGroupName in $Location" -ForegroundColor Yellow
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
        Environment = $Environment
        Application = "HybridUserSync"
        ManagedBy   = "Bicep"
    } | Out-Null
    Write-Host "✓ Resource group created" -ForegroundColor Green
}
else {
    Write-Host "✓ Resource group exists" -ForegroundColor Green
}

# Validate template
Write-Host ""
Write-Host "Validating Bicep template..." -ForegroundColor Yellow
try {
    $validation = Test-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "main.bicep" `
        -TemplateParameterFile $ParametersFile
    
    if ($validation) {
        Write-Host "✗ Template validation failed:" -ForegroundColor Red
        $validation | Format-List
        exit 1
    }
    Write-Host "✓ Template validation passed" -ForegroundColor Green
}
catch {
    Write-Host "✗ Template validation error: $_" -ForegroundColor Red
    exit 1
}

# Deploy
Write-Host ""
Write-Host "Starting deployment..." -ForegroundColor Yellow
Write-Host "This may take 5-10 minutes..." -ForegroundColor Gray
Write-Host ""

try {
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "main.bicep" `
        -TemplateParameterFile $ParametersFile `
        -Name "hybriduser-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        -Verbose
    
    Write-Host ""
    Write-Host "✓ Deployment completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "✗ Deployment failed: $_" -ForegroundColor Red
    exit 1
}

# Display outputs
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Outputs" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Logic App Name:          $($deployment.Outputs.logicAppName.Value)" -ForegroundColor White
Write-Host "Renewal Logic App:       $($deployment.Outputs.renewalLogicAppName.Value)" -ForegroundColor White
Write-Host "Key Vault Name:          $($deployment.Outputs.keyVaultName.Value)" -ForegroundColor White
Write-Host "Managed Identity ID:     $($deployment.Outputs.managedIdentityPrincipalId.Value)" -ForegroundColor White
Write-Host "Log Analytics ID:        $($deployment.Outputs.logAnalyticsWorkspaceId.Value)" -ForegroundColor White
Write-Host "Dead Letter Storage:     $($deployment.Outputs.deadLetterStorageAccountName.Value)" -ForegroundColor White
Write-Host "Action Group:            $($deployment.Outputs.actionGroupName.Value)" -ForegroundColor White
Write-Host ""

# Save outputs to file
$outputFile = "deployment-outputs-$Environment.json"
$deployment.Outputs | ConvertTo-Json -Depth 10 | Out-File $outputFile
Write-Host "Outputs saved to: $outputFile" -ForegroundColor Gray
Write-Host ""

# Next steps
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Grant Microsoft Graph permissions to the Managed Identity:" -ForegroundColor Yellow
Write-Host "   Run: .\grant-permissions.ps1 -PrincipalId $($deployment.Outputs.managedIdentityPrincipalId.Value)" -ForegroundColor White
Write-Host ""
Write-Host "2. Configure the webhook callback URL:" -ForegroundColor Yellow
Write-Host "   Run: .\configure-webhook.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor White
Write-Host ""
Write-Host "3. Verify the renewal Logic App has run successfully:" -ForegroundColor Yellow
Write-Host "   Check in Azure Portal → Logic Apps → $($deployment.Outputs.renewalLogicAppName.Value)" -ForegroundColor White
Write-Host ""
Write-Host "4. Check Key Vault for subscription ID:" -ForegroundColor Yellow
Write-Host "   Azure Portal → Key Vault → $($deployment.Outputs.keyVaultName.Value) → Secrets" -ForegroundColor White
Write-Host ""
Write-Host "5. Monitor Log Analytics for events:" -ForegroundColor Yellow
Write-Host "   Query: HybridUserSync_CL | order by TimeGenerated desc" -ForegroundColor White
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
