#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Grant Microsoft Graph permissions to managed identity for group membership synchronization
.DESCRIPTION
    This script grants the required Graph API permissions to a managed identity (VM or other resource)
    to enable reading Entra ID groups and their members for synchronization with on-premises AD groups.
.PARAMETER PrincipalId
    The Object ID (Principal ID) of the managed identity that needs permissions
.PARAMETER ResourceName
    Optional: Name of the Azure resource (for display purposes)
.EXAMPLE
    .\Grant-GroupSyncPermissions.ps1 -PrincipalId "12345678-1234-1234-1234-123456789abc"
.EXAMPLE
    .\Grant-GroupSyncPermissions.ps1 -PrincipalId "12345678-1234-1234-1234-123456789abc" -ResourceName "DC01-VM"
.NOTES
    Required permissions to run this script:
    - Application Administrator or Global Administrator role
    - Or custom role with permission to manage service principal app role assignments
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Object ID of the managed identity")]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$PrincipalId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceName = "Managed Identity"
)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Grant Group Sync Permissions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource: $ResourceName" -ForegroundColor White
Write-Host "Principal ID: $PrincipalId" -ForegroundColor White
Write-Host ""

# Verify managed identity exists
Write-Host "1. Verifying managed identity..." -ForegroundColor Yellow
try {
    $managedIdentity = az ad sp show --id $PrincipalId | ConvertFrom-Json
    if (-not $managedIdentity) {
        throw "Managed identity not found"
    }
    Write-Host "  ✓ Found: $($managedIdentity.displayName)" -ForegroundColor Green
    Write-Host "  Service Principal Type: $($managedIdentity.servicePrincipalType)" -ForegroundColor Gray
}
catch {
    Write-Host "  ✗ Failed to find managed identity: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Make sure the Principal ID is correct and you have sufficient permissions" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Get Microsoft Graph Service Principal ID
Write-Host "2. Getting Microsoft Graph service principal..." -ForegroundColor Yellow
try {
    $MSGRAPH_SP_ID = az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv
    
    if (-not $MSGRAPH_SP_ID) {
        throw "Microsoft Graph service principal not found"
    }
    
    Write-Host "  ✓ Microsoft Graph SP ID: $MSGRAPH_SP_ID" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to get Microsoft Graph service principal: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Define required permissions for group membership sync
$permissions = @(
    @{
        Name = "Group.Read.All"
        Id = "5b567255-7703-4780-807c-7be8301ae99b"
        Description = "Read all groups and their properties"
    },
    @{
        Name = "GroupMember.Read.All"
        Id = "98830695-27a2-44f7-8c18-0c3ebc9698f6"
        Description = "Read group memberships"
    },
    @{
        Name = "User.Read.All"
        Id = "df021288-bdef-4463-88db-98f22de89214"
        Description = "Read user profiles (to get on-premises identifiers)"
    }
)

Write-Host "3. Granting Graph API permissions..." -ForegroundColor Yellow
Write-Host ""

$successCount = 0
$errorCount = 0
$alreadyGrantedCount = 0

foreach ($perm in $permissions) {
    Write-Host "  Granting: $($perm.Name)" -ForegroundColor Cyan
    Write-Host "    $($perm.Description)" -ForegroundColor Gray
    
    # Create temp file for request body to avoid escaping issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $requestBody = @{
            principalId = $PrincipalId
            resourceId = $MSGRAPH_SP_ID
            appRoleId = $perm.Id
        } | ConvertTo-Json
        
        $requestBody | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
        
        # Grant the permission
        $result = az rest `
            --method POST `
            --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
            --body "@$tempFile" `
            --headers "Content-Type=application/json" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ Granted successfully" -ForegroundColor Green
            $successCount++
        }
        elseif ($result -match "Permission being assigned already exists") {
            Write-Host "    ✓ Already granted" -ForegroundColor Green
            $alreadyGrantedCount++
            $successCount++
        }
        else {
            Write-Host "    ✗ Failed to grant" -ForegroundColor Red
            Write-Host "    Error: $result" -ForegroundColor Gray
            $errorCount++
        }
    }
    catch {
        Write-Host "    ✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
}

# Optional: Grant additional permissions that might be useful
Write-Host "4. Optional permissions (for enhanced functionality)..." -ForegroundColor Yellow

$optionalPermissions = @(
    @{
        Name = "Directory.Read.All"
        Id = "7ab1d382-f21e-4acd-a863-ba3e13f7da61"
        Description = "Read directory data (for organizational units, etc.)"
        Reason = "Useful for filtering groups by administrative units"
    }
)

foreach ($perm in $optionalPermissions) {
    Write-Host "  Optional: $($perm.Name)" -ForegroundColor Yellow
    Write-Host "    $($perm.Description)" -ForegroundColor Gray
    Write-Host "    Reason: $($perm.Reason)" -ForegroundColor Gray
    
    $response = Read-Host "    Grant this permission? (y/n)"
    
    if ($response -eq 'y' -or $response -eq 'Y') {
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $requestBody = @{
                principalId = $PrincipalId
                resourceId = $MSGRAPH_SP_ID
                appRoleId = $perm.Id
            } | ConvertTo-Json
            
            $requestBody | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
            
            $result = az rest `
                --method POST `
                --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
                --body "@$tempFile" `
                --headers "Content-Type=application/json" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    ✓ Granted successfully" -ForegroundColor Green
                $successCount++
            }
            elseif ($result -match "Permission being assigned already exists") {
                Write-Host "    ✓ Already granted" -ForegroundColor Green
                $alreadyGrantedCount++
                $successCount++
            }
            else {
                Write-Host "    ✗ Failed to grant" -ForegroundColor Red
                Write-Host "    Error: $result" -ForegroundColor Gray
                $errorCount++
            }
        }
        catch {
            Write-Host "    ✗ Exception: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
        finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "    - Skipped" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Permission Grant Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Successfully granted: $successCount" -ForegroundColor Green

if ($alreadyGrantedCount -gt 0) {
    Write-Host "Already had permissions: $alreadyGrantedCount" -ForegroundColor Yellow
}

if ($errorCount -gt 0) {
    Write-Host "Errors encountered: $errorCount" -ForegroundColor Red
}

Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "✓ All required permissions have been granted!" -ForegroundColor Green
    Write-Host ""
    Write-Host "The managed identity can now:" -ForegroundColor Cyan
    Write-Host "  • Read Entra ID groups and their properties" -ForegroundColor White
    Write-Host "  • Read group memberships" -ForegroundColor White
    Write-Host "  • Read user profiles (for on-premises mapping)" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Deploy the Sync-GroupMembership.ps1 script to your domain controller" -ForegroundColor White
    Write-Host "  2. Update the TargetOU parameter in the script" -ForegroundColor White
    Write-Host "  3. Test with -WhatIf flag first" -ForegroundColor White
    Write-Host "  4. Set up scheduled task for regular synchronization" -ForegroundColor White
}
else {
    Write-Host "⚠ Some permissions failed to be granted." -ForegroundColor Yellow
    Write-Host "Please check the errors above and retry if needed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "  • Insufficient admin privileges" -ForegroundColor Gray
    Write-Host "  • Incorrect Principal ID" -ForegroundColor Gray
    Write-Host "  • Network connectivity issues" -ForegroundColor Gray
}

Write-Host ""

# Show current permissions for verification
Write-Host "Current permissions for this managed identity:" -ForegroundColor Cyan
try {
    $currentPerms = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" | ConvertFrom-Json
    
    if ($currentPerms.value) {
        $graphPerms = $currentPerms.value | Where-Object { $_.resourceId -eq $MSGRAPH_SP_ID }
        
        if ($graphPerms) {
            Write-Host "Microsoft Graph permissions:" -ForegroundColor Gray
            foreach ($assignment in $graphPerms) {
                # Get the role name from Graph
                $role = az rest --method GET --url "https://graph.microsoft.com/v1.0/servicePrincipals/$MSGRAPH_SP_ID" --query "appRoles[?id=='$($assignment.appRoleId)'].value | [0]" -o tsv 2>$null
                if ($role) {
                    Write-Host "  • $role" -ForegroundColor Green
                } else {
                    Write-Host "  • $($assignment.appRoleId)" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "  No Graph permissions found" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  No permissions found" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Could not retrieve current permissions" -ForegroundColor Yellow
}

Write-Host ""