# Grant Microsoft Graph API Permissions to Managed Identity
# This script grants the required permissions for the Logic Apps to interact with Entra ID

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PrincipalId,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Grant Graph API Permissions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Managed Identity Principal ID: $PrincipalId" -ForegroundColor White
Write-Host ""

# Check if Microsoft.Graph module is installed
Write-Host "Checking PowerShell modules..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "Microsoft.Graph.Applications module not found. Installing..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
    Write-Host "✓ Module installed" -ForegroundColor Green
}

# Connect to Microsoft Graph
Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Write-Host "You may be prompted to sign in with admin credentials" -ForegroundColor Gray
try {
    Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

# Get Microsoft Graph Service Principal
Write-Host ""
Write-Host "Finding Microsoft Graph service principal..." -ForegroundColor Yellow
$graphSP = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
if (-not $graphSP) {
    Write-Host "✗ Microsoft Graph service principal not found" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Found Microsoft Graph SP: $($graphSP.Id)" -ForegroundColor Green

# Define required permissions
$requiredPermissions = @(
    @{
        Name  = "User.Read.All"
        Id    = "df021288-bdef-4463-88db-98f22de89214"
        Type  = "Role"
        Desc  = "Read all users' full profiles"
    },
    @{
        Name  = "AdministrativeUnit.Read.All"
        Id    = "134fd756-38ce-4afd-ba33-e9623dbe66c2"
        Type  = "Role"
        Desc  = "Read all administrative units"
    },
    @{
        Name  = "Directory.ReadWrite.All"
        Id    = "19dbc75e-c2e2-444c-a770-ec69d8559fc7"
        Type  = "Role"
        Desc  = "Read and write directory data"
    }
)

Write-Host ""
Write-Host "Permissions to be granted:" -ForegroundColor Yellow
$requiredPermissions | ForEach-Object {
    Write-Host "  • $($_.Name) - $($_.Desc)" -ForegroundColor White
}
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode - no changes will be made" -ForegroundColor Cyan
    Write-Host ""
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Confirm
$confirm = Read-Host "Grant these permissions? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled by user" -ForegroundColor Yellow
    Disconnect-MgGraph | Out-Null
    exit 0
}

# Grant permissions
Write-Host ""
Write-Host "Granting permissions..." -ForegroundColor Yellow
$successCount = 0
$errorCount = 0

foreach ($permission in $requiredPermissions) {
    Write-Host "  Granting $($permission.Name)..." -ForegroundColor Gray
    
    try {
        # Check if already assigned
        $existingAssignment = Get-MgServicePrincipalAppRoleAssignment `
            -ServicePrincipalId $PrincipalId `
            -Filter "appRoleId eq '$($permission.Id)' and resourceId eq '$($graphSP.Id)'" `
            -ErrorAction SilentlyContinue
        
        if ($existingAssignment) {
            Write-Host "    ℹ Already assigned" -ForegroundColor Cyan
            $successCount++
        }
        else {
            # Grant permission
            $params = @{
                principalId = $PrincipalId
                resourceId  = $graphSP.Id
                appRoleId   = $permission.Id
            }
            
            try {
                New-MgServicePrincipalAppRoleAssignment `
                    -ServicePrincipalId $PrincipalId `
                    -BodyParameter $params `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "    ✓ Granted" -ForegroundColor Green
                $successCount++
            }
            catch {
                # Check if error is "already exists"
                if ($_.Exception.Message -like "*already exists*") {
                    Write-Host "    ℹ Already assigned" -ForegroundColor Cyan
                    $successCount++
                }
                else {
                    throw
                }
            }
        }
    }
    catch {
        Write-Host "    ✗ Failed: $_" -ForegroundColor Red
        $errorCount++
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successfully granted: $successCount" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "Errors: $errorCount" -ForegroundColor Red
}
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null

if ($errorCount -eq 0) {
    Write-Host "✓ All permissions granted successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: Verify the renewal Logic App has created the Graph subscription" -ForegroundColor Yellow
}
else {
    Write-Host "⚠ Some permissions failed to grant. Please check errors above." -ForegroundColor Yellow
}

Write-Host ""
