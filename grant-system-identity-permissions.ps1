#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Grant Microsoft Graph API permissions to Logic App's system-assigned managed identity
.DESCRIPTION
    Grants the required Graph API permissions including Synchronization.ReadWrite.All
    to a Logic App's system-assigned managed identity using az rest API
.EXAMPLE
    .\grant-system-identity-permissions.ps1 -PrincipalId "90224abd-7a42-471e-a69f-0b39219b2069"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PrincipalId
)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Grant Graph Permissions to System Identity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Principal ID: $PrincipalId" -ForegroundColor White
Write-Host ""

# Get Microsoft Graph Service Principal ID
Write-Host "Getting Microsoft Graph service principal..." -ForegroundColor Yellow
$MSGRAPH_SP_ID = az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv

if (-not $MSGRAPH_SP_ID) {
    Write-Host "✗ Failed to get Microsoft Graph service principal" -ForegroundColor Red
    exit 1
}

Write-Host "  Microsoft Graph SP ID: $MSGRAPH_SP_ID" -ForegroundColor White
Write-Host ""

# Define permissions with their IDs
$permissions = @(
 
@{
        Name = "User.Read.All"
        Id = "df021288-bdef-4463-88db-98f22de89214"
        Description = "Read all users' full profiles"
    },
    @{
        Name = "AdministrativeUnit.Read.All"
        Id = "134fd756-38ce-4afd-ba33-e9623dbe66c2"
        Description = "Read administrative units"
    },
    @{
        Name = "Synchronization.ReadWrite.All"
        Id = "9b50c33d-700f-43b1-b2eb-87e89b703581"
        Description = "Manage synchronization jobs"
    },
    @{
        Name = "SynchronizationData-User.Upload"
        Id = "db31e92a-b9ea-4d87-bf6a-75a37a9ca35a"
        Description = "Upload bulk user data to identity synchronization service"
    },
    @{
        Name = "User-OnPremisesSyncBehavior.ReadWrite.All"
        Id = "a94a502d-0281-4d15-8cd2-682ac9362c4c"
        Description = "Read and write user source of authority (SOA) settings"
    }
)

Write-Host "Granting permissions..." -ForegroundColor Yellow
Write-Host ""

$successCount = 0
$errorCount = 0

foreach ($perm in $permissions) {
    Write-Host "  $($perm.Name)" -ForegroundColor Cyan
    Write-Host "    $($perm.Description)" -ForegroundColor Gray
    
    # Create temp file for body to avoid escaping issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    @{
        principalId = $PrincipalId
        resourceId = $MSGRAPH_SP_ID
        appRoleId = $perm.Id
    } | ConvertTo-Json | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
    
    $result = az rest `
        --method POST `
        --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
        --body "@$tempFile" `
        --headers "Content-Type=application/json" 2>&1
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ Granted" -ForegroundColor Green
        $successCount++
    }
    elseif ($result -match "Permission being assigned already exists on the object") {
        Write-Host "    ✓ Already granted" -ForegroundColor Green
        $successCount++
    }
    else {
        Write-Host "    ✗ Failed" -ForegroundColor Red
        Write-Host "    Error: $result" -ForegroundColor Gray
        $errorCount++
    }
    
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successfully granted: $successCount / $($permissions.Count)" -ForegroundColor $(if ($successCount -eq $permissions.Count) { "Green" } else { "Yellow" })

if ($errorCount -gt 0) {
    Write-Host "Errors: $errorCount" -ForegroundColor Red
}

Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "✓ All permissions granted successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The Logic App can now:" -ForegroundColor Cyan
    Write-Host "  • Read user details from Microsoft Graph" -ForegroundColor White
    Write-Host "  • Check administrative unit membership" -ForegroundColor White
    Write-Host "  • Update source of authority" -ForegroundColor White
    Write-Host "  • Provision users to AD DS via SCIM bulk upload" -ForegroundColor White
}
else {
    Write-Host "⚠ Some permissions failed. Please check errors above." -ForegroundColor Yellow
}

Write-Host ""
