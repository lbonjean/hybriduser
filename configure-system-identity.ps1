# Configure System-Assigned Managed Identity Permissions
# This script grants the Logic App's system-assigned managed identity the necessary permissions

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$LogicAppName,
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configure Logic App Managed Identity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get Logic App details (Logic Apps are workflows in Microsoft.Logic namespace)
Write-Host "Getting Logic App details..." -ForegroundColor Yellow
$logicAppJson = az resource show `
    --name $LogicAppName `
    --resource-group $ResourceGroupName `
    --resource-type "Microsoft.Logic/workflows" `
    --query '{id:id,principalId:identity.principalId,tenantId:identity.tenantId,identityType:identity.type}'

$logicApp = $logicAppJson | ConvertFrom-Json

if (-not $logicApp.principalId) {
    Write-Host "✗ Logic App does not have a system-assigned managed identity!" -ForegroundColor Red
    Write-Host "  The Logic App should have been deployed with SystemAssigned identity." -ForegroundColor Yellow
    Write-Host "  Please redeploy the Logic App with the updated Bicep template." -ForegroundColor Yellow
    exit 1
}

Write-Host "  Logic App: $LogicAppName" -ForegroundColor Green
Write-Host "  Principal ID: $($logicApp.principalId)" -ForegroundColor White

# Get the App ID from the service principal
$spJson = az ad sp show --id $logicApp.principalId --query '{appId:appId,displayName:displayName}'
$sp = $spJson | ConvertFrom-Json
$logicApp | Add-Member -MemberType NoteProperty -Name "appId" -Value $sp.appId

Write-Host "  App ID: $($logicApp.appId)" -ForegroundColor White
Write-Host ""

# Required Microsoft Graph permissions
$permissions = @(
    @{
        AppRole = "User.Read.All"
        Description = "Read all users' full profiles"
    },
    @{
        AppRole = "AdministrativeUnit.Read.All"
        Description = "Read administrative units"
    },
    @{
        AppRole = "Directory.ReadWrite.All"
        Description = "Read and write directory data (for source of authority)"
    },
    @{
        AppRole = "Synchronization.ReadWrite.All"
        Description = "Manage synchronization jobs and perform bulk upload"
    }
)

# Get Microsoft Graph Service Principal
Write-Host "Getting Microsoft Graph service principal..." -ForegroundColor Yellow
$graphSpJson = az ad sp list --filter "displayName eq 'Microsoft Graph'" --query "[0]" 
$graphSp = $graphSpJson | ConvertFrom-Json

if (-not $graphSp) {
    Write-Host "✗ Could not find Microsoft Graph service principal" -ForegroundColor Red
    exit 1
}

Write-Host "  Microsoft Graph App ID: $($graphSp.appId)" -ForegroundColor White
Write-Host ""

# Grant permissions
Write-Host "Step 1: Adding API permissions to app registration..." -ForegroundColor Yellow
Write-Host ""

# Get the app registration object ID (we need this, not the service principal ID)
$appObjectId = az ad app show --id $logicApp.appId --query id -o tsv
Write-Host "  App Registration Object ID: $appObjectId" -ForegroundColor Gray
Write-Host ""

foreach ($perm in $permissions) {
    Write-Host "  Adding: $($perm.AppRole)" -ForegroundColor Cyan
    Write-Host "    $($perm.Description)" -ForegroundColor Gray
    
    # Find the app role ID
    $appRole = $graphSp.appRoles | Where-Object { $_.value -eq $perm.AppRole } | Select-Object -First 1
    
    if (-not $appRole) {
        Write-Host "    ✗ App role not found!" -ForegroundColor Red
        continue
    }
    
    # Add permission to app registration using az ad app permission add
    $addResult = az ad app permission add `
        --id $appObjectId `
        --api $graphSp.appId `
        --api-permissions "$($appRole.id)=Role" `
        2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ Permission added" -ForegroundColor Green
    } elseif ($addResult -match "already exists|Conflict") {
        Write-Host "    ✓ Already added" -ForegroundColor Green
    } else {
        Write-Host "    ⚠ $addResult" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

Write-Host ""
Write-Host "Step 2: Granting admin consent..." -ForegroundColor Yellow
Write-Host ""

# Grant admin consent for all permissions at once
$consentResult = az ad app permission admin-consent --id $appObjectId 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Admin consent granted successfully!" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to grant admin consent automatically" -ForegroundColor Red
    Write-Host "  Error: $consentResult" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Please grant admin consent manually:" -ForegroundColor Yellow
    Write-Host "  1. Go to Azure Portal > Entra ID > App registrations" -ForegroundColor Gray
    Write-Host "  2. Search for Object ID: $appObjectId" -ForegroundColor Gray
    Write-Host "  3. Go to 'API permissions'" -ForegroundColor Gray
    Write-Host "  4. Click 'Grant admin consent for [your tenant]'" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Logic App: $LogicAppName" -ForegroundColor White
Write-Host "  Principal ID: $($logicApp.principalId)" -ForegroundColor White
Write-Host "  Permissions: $($permissions.Count) Microsoft Graph app roles" -ForegroundColor White
Write-Host ""
Write-Host "The Logic App can now:" -ForegroundColor Green
Write-Host "  ✓ Read user details from Microsoft Graph" -ForegroundColor White
Write-Host "  ✓ Check administrative unit membership" -ForegroundColor White
Write-Host "  ✓ Update source of authority" -ForegroundColor White
Write-Host "  ✓ Provision users to AD DS via SCIM API" -ForegroundColor White
Write-Host ""
