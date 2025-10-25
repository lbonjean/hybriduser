#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Synchronize group membership between Entra ID and on-premises Active Directory
.DESCRIPTION
    This script runs on a domain controller with managed identity and synchronizes group membership:
    - Reads AD groups from specified OU
    - Extracts Entra ID group GUID from AD group description
    - Compares membership between Entra and AD groups
    - Adds/removes members to keep AD groups in sync with Entra groups
.EXAMPLE
    .\Sync-GroupMembership.ps1
.NOTES
    Requires:
    - Domain controller with managed identity
    - Microsoft Graph PowerShell SDK or Azure CLI
    - Active Directory PowerShell module
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "OU=Groups,OU=Mirror,OU=Hybrid,DC=C0094,DC=azure",  # Fill in your OU path
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$DetailedLogging = $false
)

$ErrorActionPreference = "Continue"

# Import required modules
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    if ($DetailedLogging) { Write-Host "[OK] Active Directory module loaded" -ForegroundColor Green }
}
catch {
    Write-Host "[ERROR] Failed to import Active Directory module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Group Membership Sync (Entra <-> AD)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Target OU: $TargetOU" -ForegroundColor White
Write-Host "Mode: $(if($WhatIf) { 'SIMULATION (WhatIf)' } else { 'LIVE SYNC' })" -ForegroundColor $(if($WhatIf) { 'Yellow' } else { 'Green' })
Write-Host "Detailed Logging: $(if($DetailedLogging) { 'ON' } else { 'OFF' })" -ForegroundColor $(if($DetailedLogging) { 'Green' } else { 'Gray' })
Write-Host ""

# Function to get access token using managed identity
function Get-ManagedIdentityToken {
    try {
        $tokenResponse = Invoke-RestMethod -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://graph.microsoft.com" -Headers @{Metadata="true"}
        return $tokenResponse.access_token
    }
    catch {
        Write-Host "✗ Failed to get managed identity token: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Function to call Microsoft Graph API
function Invoke-GraphAPI {
    param(
        [string]$Uri,
        [string]$AccessToken,
        [string]$Method = "GET"
    )
    
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }
    
    try {
        return Invoke-RestMethod -Uri $Uri -Headers $headers -Method $Method
    }
    catch {
        Write-Host "✗ Graph API call failed: $Uri" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Gray
        throw
    }
}

# Function to extract GUID from description
function Get-EntraGroupGuid {
    param([string]$Description)
    
    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $null
    }
    
    # Try to parse as GUID (description contains only the GUID)
    $guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    if ($Description -match $guidPattern) {
        return $Description.Trim()
    }
    
    return $null
}

# Function to get Entra group members
function Get-EntraGroupMembers {
    param(
        [string]$GroupId,
        [string]$AccessToken
    )
    
    $members = @()
    $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members?`$select=id,userPrincipalName,onPremisesSecurityIdentifier,onPremisesSamAccountName"
    
    do {
        $response = Invoke-GraphAPI -Uri $uri -AccessToken $AccessToken
        $members += $response.value
        $uri = $response.'@odata.nextLink'
    } while ($uri)
    
    return $members
}

# Function to get AD group members
function Get-ADGroupMembersInfo {
    param([string]$GroupName)
    
    try {
        $members = Get-ADGroupMember -Identity $GroupName -ErrorAction Stop
        $memberInfo = @()
        
        foreach ($member in $members) {
            if ($member.objectClass -eq 'user') {
                try {
                    $user = Get-ADUser -Identity $member.SamAccountName -Properties UserPrincipalName, ObjectSID -ErrorAction Stop
                    $memberInfo += @{
                        SamAccountName = $user.SamAccountName
                        UserPrincipalName = $user.UserPrincipalName
                        ObjectSID = $user.ObjectSID.Value
                        DistinguishedName = $user.DistinguishedName
                    }
                }
                catch {
                    if ($DetailedLogging) { Write-Host "  Warning: Could not get details for user $($member.SamAccountName)" -ForegroundColor Yellow }
                }
            }
        }
        
        return $memberInfo
    }
    catch {
        Write-Host "  ✗ Failed to get AD group members: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Main execution
try {
    # Get managed identity token
    Write-Host "1. Getting managed identity token..." -ForegroundColor Yellow
    $accessToken = Get-ManagedIdentityToken
    if ($DetailedLogging) { Write-Host "  ✓ Token acquired" -ForegroundColor Green }
    Write-Host ""
    
    # Get AD groups from target OU
    Write-Host "2. Reading AD groups from OU..." -ForegroundColor Yellow
    try {
        $adGroups = Get-ADGroup -Filter * -SearchBase $TargetOU -Properties Description -ErrorAction Stop
        Write-Host "  ✓ Found $($adGroups.Count) groups in $TargetOU" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to read groups from OU: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    
    # Process each group
    Write-Host "3. Processing groups..." -ForegroundColor Yellow
    Write-Host ""
    
    $processedCount = 0
    $syncedCount = 0
    $errorCount = 0
    
    foreach ($adGroup in $adGroups) {
        $processedCount++
        Write-Host "Processing: $($adGroup.Name)" -ForegroundColor Cyan
        
        # Extract Entra group GUID from description
        $entraGroupGuid = Get-EntraGroupGuid -Description $adGroup.Description
        
        if (-not $entraGroupGuid) {
            Write-Host "  ⚠ No valid GUID found in description: '$($adGroup.Description)'" -ForegroundColor Yellow
            Write-Host ""
            continue
        }
        
        Write-Host "  Entra Group ID: $entraGroupGuid" -ForegroundColor Gray
        
        try {
            # Get Entra group members
            if ($DetailedLogging) { Write-Host "  Getting Entra group members..." -ForegroundColor Gray }
            $entraMembers = Get-EntraGroupMembers -GroupId $entraGroupGuid -AccessToken $accessToken
            
            # Filter to only users that exist on-premises (have onPremisesSecurityIdentifier)
            $entraOnPremUsers = $entraMembers | Where-Object { 
                $_.onPremisesSecurityIdentifier -and $_.onPremisesSamAccountName 
            }
            
            Write-Host "  Entra members (on-prem): $($entraOnPremUsers.Count)" -ForegroundColor Gray
            
            # Get current AD group members
            if ($DetailedLogging) { Write-Host "  Getting AD group members..." -ForegroundColor Gray }
            $adMembers = Get-ADGroupMembersInfo -GroupName $adGroup.Name
            Write-Host "  AD members: $($adMembers.Count)" -ForegroundColor Gray
            
            # Compare memberships
            $entraUserSIDs = $entraOnPremUsers | ForEach-Object { $_.onPremisesSecurityIdentifier }
            $adUserSIDs = $adMembers | ForEach-Object { $_.ObjectSID }
            
            # Users to add (in Entra but not in AD)
            $usersToAdd = $entraOnPremUsers | Where-Object { 
                $_.onPremisesSecurityIdentifier -notin $adUserSIDs 
            }
            
            # Users to remove (in AD but not in Entra)
            $usersToRemove = $adMembers | Where-Object { 
                $_.ObjectSID -notin $entraUserSIDs 
            }
            
            # Apply changes
            $changesApplied = $false
            
            # Add users
            foreach ($userToAdd in $usersToAdd) {
                $samAccountName = $userToAdd.onPremisesSamAccountName
                Write-Host "  + Adding: $samAccountName" -ForegroundColor Green
                
                if (-not $WhatIf) {
                    try {
                        Add-ADGroupMember -Identity $adGroup.Name -Members $samAccountName -ErrorAction Stop
                        Write-Host "    ✓ Added successfully" -ForegroundColor Green
                        $changesApplied = $true
                    }
                    catch {
                        Write-Host "    ✗ Failed to add: $($_.Exception.Message)" -ForegroundColor Red
                        $errorCount++
                    }
                } else {
                    Write-Host "    (SIMULATION - would add)" -ForegroundColor Yellow
                }
            }
            
            # Remove users
            foreach ($userToRemove in $usersToRemove) {
                $samAccountName = $userToRemove.SamAccountName
                Write-Host "  - Removing: $samAccountName" -ForegroundColor Red
                
                if (-not $WhatIf) {
                    try {
                        Remove-ADGroupMember -Identity $adGroup.Name -Members $samAccountName -Confirm:$false -ErrorAction Stop
                        Write-Host "    ✓ Removed successfully" -ForegroundColor Green
                        $changesApplied = $true
                    }
                    catch {
                        Write-Host "    ✗ Failed to remove: $($_.Exception.Message)" -ForegroundColor Red
                        $errorCount++
                    }
                } else {
                    Write-Host "    (SIMULATION - would remove)" -ForegroundColor Yellow
                }
            }
            
            if ($usersToAdd.Count -eq 0 -and $usersToRemove.Count -eq 0) {
                Write-Host "  ✓ Already in sync" -ForegroundColor Green
            }
            
            if ($changesApplied -or ($WhatIf -and ($usersToAdd.Count -gt 0 -or $usersToRemove.Count -gt 0))) {
                $syncedCount++
            }
        }
        catch {
            Write-Host "  ✗ Error processing group: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
        
        Write-Host ""
    }
    
    # Summary
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Sync Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Groups processed: $processedCount" -ForegroundColor White
    Write-Host "Groups synchronized: $syncedCount" -ForegroundColor Green
    
    if ($errorCount -gt 0) {
        Write-Host "Errors encountered: $errorCount" -ForegroundColor Red
    }
    
    if ($WhatIf) {
        Write-Host ""
        Write-Host "⚠ SIMULATION MODE - No actual changes were made" -ForegroundColor Yellow
        Write-Host "Run without -WhatIf to apply changes" -ForegroundColor Yellow
    }
    
    Write-Host ""
}
catch {
    Write-Host "✗ Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}