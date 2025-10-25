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
    - Logs to Event Log and optionally to Log Analytics
    - Can create scheduled task for automated runs
.PARAMETER TargetOUPath
    The relative OU path containing groups to synchronize (domain will be auto-detected)
    Example: "OU=Groups,OU=Mirror,OU=Hybrid"
.PARAMETER WhatIf
    Run in simulation mode without making actual changes
.PARAMETER DetailedLogging
    Enable detailed console logging
.PARAMETER CreateScheduledTask
    Create a Windows scheduled task to run this script daily
.PARAMETER LogAnalyticsWorkspaceId
    Log Analytics Workspace ID for remote logging
.PARAMETER LogAnalyticsSharedKey
    Log Analytics Shared Key for authentication
.PARAMETER TaskName
    Name for the scheduled task (default: GroupMembershipSync)
.EXAMPLE
    .\Sync-GroupMembership-ASCII.ps1 -WhatIf
    Run in simulation mode
.EXAMPLE
    .\Sync-GroupMembership-ASCII.ps1 -CreateScheduledTask
    Create scheduled task and run sync
.EXAMPLE
    .\Sync-GroupMembership-ASCII.ps1 -TargetOUPath "OU=TestGroups,OU=Sync" -WhatIf
    Run in simulation mode with custom OU path
.NOTES
    Requires:
    - Domain controller with managed identity
    - Graph API permissions: Group.Read.All, GroupMember.Read.All, User.Read.All
    - Active Directory PowerShell module
    - Administrator privileges (for Event Log and scheduled tasks)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TargetOUPath = "OU=Groups,OU=Mirror,OU=Hybrid",  # Relative OU path (domain will be auto-detected)
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$DetailedLogging = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateScheduledTask = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsWorkspaceId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$LogAnalyticsSharedKey = "",
    
    [Parameter(Mandatory=$false)]
    [string]$TaskName = "GroupMembershipSync"
)

$ErrorActionPreference = "Continue"

# Function to get domain distinguished name
function Get-DomainDN {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        return $domain.DistinguishedName
    }
    catch {
        Write-Host "[ERROR] Failed to get domain information: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Function to build complete OU path
function Get-CompleteOUPath {
    param([string]$RelativeOUPath)
    
    $domainDN = Get-DomainDN
    $completeOU = "$RelativeOUPath,$domainDN"
    
    if ($DetailedLogging) { 
        Write-Host "[INFO] Domain DN: $domainDN" -ForegroundColor Gray
        Write-Host "[INFO] Complete OU: $completeOU" -ForegroundColor Gray
    }
    
    return $completeOU
}

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

# Build complete OU path
try {
    $TargetOU = Get-CompleteOUPath -RelativeOUPath $TargetOUPath
    Write-Host "Target OU: $TargetOU" -ForegroundColor White
}
catch {
    Write-Host "[ERROR] Failed to determine target OU: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

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
        Write-Host "[ERROR] Failed to get managed identity token: $($_.Exception.Message)" -ForegroundColor Red
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
        Write-Host "[ERROR] Graph API call failed: $Uri" -ForegroundColor Red
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
        Write-Host "  [ERROR] Failed to get AD group members: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Function to write to Event Log
function Write-EventLogEntry {
    param(
        [string]$Message,
        [string]$EventType = "Information",
        [int]$EventId = 1000
    )
    
    try {
        $logName = "Application"
        $source = "GroupMembershipSync"
        
        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName $logName -Source $source
        }
        
        Write-EventLog -LogName $logName -Source $source -EntryType $EventType -EventId $EventId -Message $Message
    }
    catch {
        if ($DetailedLogging) { Write-Host "  Warning: Could not write to Event Log: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Function to send data to Log Analytics
function Send-ToLogAnalytics {
    param(
        [string]$WorkspaceId,
        [string]$SharedKey,
        [string]$LogType,
        [object]$JsonData
    )
    
    if ([string]::IsNullOrEmpty($WorkspaceId) -or [string]::IsNullOrEmpty($SharedKey)) {
        return
    }
    
    try {
        $method = "POST"
        $contentType = "application/json"
        $resource = "/api/logs"
        $rfc1123date = [DateTime]::UtcNow.ToString("r")
        $contentLength = [System.Text.Encoding]::UTF8.GetBytes($JsonData).Length
        
        # Create the string to hash
        $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + "x-ms-date:" + $rfc1123date + "`n" + $resource
        
        # Hash the string
        $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
        $keyBytes = [Convert]::FromBase64String($SharedKey)
        $hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
        $hmacsha256.Key = $keyBytes
        $computedHash = $hmacsha256.ComputeHash($bytesToHash)
        $encodedHash = [Convert]::ToBase64String($computedHash)
        $authorization = 'SharedKey {0}:{1}' -f $WorkspaceId, $encodedHash
        
        # Create the URI and headers
        $uri = "https://" + $WorkspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
        $headers = @{
            "Authorization" = $authorization
            "Log-Type" = $LogType
            "x-ms-date" = $rfc1123date
        }
        
        # Send the data
        Invoke-RestMethod -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $JsonData | Out-Null
        
        if ($DetailedLogging) { Write-Host "  [OK] Sent data to Log Analytics" -ForegroundColor Green }
    }
    catch {
        if ($DetailedLogging) { Write-Host "  Warning: Could not send to Log Analytics: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

# Function to log sync activity
function Write-SyncLog {
    param(
        [string]$EventType,
        [string]$GroupName = "",
        [string]$UserName = "",
        [string]$Action = "",
        [string]$Details = ""
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computerName = $env:COMPUTERNAME
    
    # Event Log message
    $eventMessage = "Group Membership Sync - $EventType"
    if ($GroupName) { $eventMessage += " | Group: $GroupName" }
    if ($UserName) { $eventMessage += " | User: $UserName" }
    if ($Action) { $eventMessage += " | Action: $Action" }
    if ($Details) { $eventMessage += " | Details: $Details" }
    
    Write-EventLogEntry -Message $eventMessage -EventType $(if($EventType -eq "Error") { "Error" } else { "Information" })
    
    # Log Analytics data
    if (-not [string]::IsNullOrEmpty($LogAnalyticsWorkspaceId)) {
        $logData = @{
            Timestamp = $timestamp
            Computer = $computerName
            EventType = $EventType
            GroupName = $GroupName
            UserName = $UserName
            Action = $Action
            Details = $Details
        }
        
        $jsonData = $logData | ConvertTo-Json
        Send-ToLogAnalytics -WorkspaceId $LogAnalyticsWorkspaceId -SharedKey $LogAnalyticsSharedKey -LogType "GroupMembershipSync" -JsonData $jsonData
    }
}

# Function to create scheduled task
function New-GroupSyncScheduledTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )
    
    try {
        $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($taskExists) {
            Write-Host "[WARNING] Scheduled task '$TaskName' already exists" -ForegroundColor Yellow
            $overwrite = Read-Host "Do you want to overwrite it? (y/n)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                return
            }
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Task settings
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"  # Run daily at 2 AM
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        # Register the task
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Synchronize group membership between Entra ID and on-premises AD"
        
        Write-Host "[OK] Scheduled task '$TaskName' created successfully" -ForegroundColor Green
        Write-Host "  Schedule: Daily at 2:00 AM" -ForegroundColor Gray
        Write-Host "  Script: $ScriptPath" -ForegroundColor Gray
        
        Write-SyncLog -EventType "Information" -Details "Scheduled task '$TaskName' created"
    }
    catch {
        Write-Host "[ERROR] Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
        Write-SyncLog -EventType "Error" -Details "Failed to create scheduled task: $($_.Exception.Message)"
    }
}

# Main execution
try {
    Write-SyncLog -EventType "Information" -Details "Group membership sync started"
    
    # Create scheduled task if requested
    if ($CreateScheduledTask) {
        $currentScriptPath = $MyInvocation.MyCommand.Path
        if ($currentScriptPath) {
            New-GroupSyncScheduledTask -TaskName $TaskName -ScriptPath $currentScriptPath
            Write-Host ""
        } else {
            Write-Host "[WARNING] Cannot determine script path for scheduled task" -ForegroundColor Yellow
        }
    }
    
    # Get managed identity token
    Write-Host "1. Getting managed identity token..." -ForegroundColor Yellow
    $accessToken = Get-ManagedIdentityToken
    if ($DetailedLogging) { Write-Host "  [OK] Token acquired" -ForegroundColor Green }
    Write-Host ""
    
    # Get AD groups from target OU
    Write-Host "2. Reading AD groups from OU..." -ForegroundColor Yellow
    try {
        $adGroups = Get-ADGroup -Filter * -SearchBase $TargetOU -Properties Description -ErrorAction Stop
        Write-Host "  [OK] Found $($adGroups.Count) groups in $TargetOU" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Failed to read groups from OU: $($_.Exception.Message)" -ForegroundColor Red
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
            Write-Host "  [WARNING] No valid GUID found in description: '$($adGroup.Description)'" -ForegroundColor Yellow
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
                        Write-Host "    [OK] Added successfully" -ForegroundColor Green
                        Write-SyncLog -EventType "Information" -GroupName $adGroup.Name -UserName $samAccountName -Action "Added" -Details "User added to group successfully"
                        $changesApplied = $true
                    }
                    catch {
                        Write-Host "    [ERROR] Failed to add: $($_.Exception.Message)" -ForegroundColor Red
                        Write-SyncLog -EventType "Error" -GroupName $adGroup.Name -UserName $samAccountName -Action "Add Failed" -Details $_.Exception.Message
                        $errorCount++
                    }
                } else {
                    Write-Host "    (SIMULATION - would add)" -ForegroundColor Yellow
                    Write-SyncLog -EventType "Information" -GroupName $adGroup.Name -UserName $samAccountName -Action "Simulated Add" -Details "WhatIf mode - would add user"
                }
            }
            
            # Remove users
            foreach ($userToRemove in $usersToRemove) {
                $samAccountName = $userToRemove.SamAccountName
                Write-Host "  - Removing: $samAccountName" -ForegroundColor Red
                
                if (-not $WhatIf) {
                    try {
                        Remove-ADGroupMember -Identity $adGroup.Name -Members $samAccountName -Confirm:$false -ErrorAction Stop
                        Write-Host "    [OK] Removed successfully" -ForegroundColor Green
                        Write-SyncLog -EventType "Information" -GroupName $adGroup.Name -UserName $samAccountName -Action "Removed" -Details "User removed from group successfully"
                        $changesApplied = $true
                    }
                    catch {
                        Write-Host "    [ERROR] Failed to remove: $($_.Exception.Message)" -ForegroundColor Red
                        Write-SyncLog -EventType "Error" -GroupName $adGroup.Name -UserName $samAccountName -Action "Remove Failed" -Details $_.Exception.Message
                        $errorCount++
                    }
                } else {
                    Write-Host "    (SIMULATION - would remove)" -ForegroundColor Yellow
                    Write-SyncLog -EventType "Information" -GroupName $adGroup.Name -UserName $samAccountName -Action "Simulated Remove" -Details "WhatIf mode - would remove user"
                }
            }
            
            if ($usersToAdd.Count -eq 0 -and $usersToRemove.Count -eq 0) {
                Write-Host "  [OK] Already in sync" -ForegroundColor Green
            }
            
            if ($changesApplied -or ($WhatIf -and ($usersToAdd.Count -gt 0 -or $usersToRemove.Count -gt 0))) {
                $syncedCount++
            }
        }
        catch {
            Write-Host "  [ERROR] Error processing group: $($_.Exception.Message)" -ForegroundColor Red
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
        Write-Host "[WARNING] SIMULATION MODE - No actual changes were made" -ForegroundColor Yellow
        Write-Host "Run without -WhatIf to apply changes" -ForegroundColor Yellow
    }
    
    # Final logging
    $summaryDetails = "Processed: $processedCount, Synchronized: $syncedCount, Errors: $errorCount"
    if ($WhatIf) { $summaryDetails += " (WhatIf mode)" }
    Write-SyncLog -EventType "Information" -Details "Group membership sync completed - $summaryDetails"
    
    Write-Host ""
}
catch {
    Write-Host "[ERROR] Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Write-SyncLog -EventType "Error" -Details "Fatal error: $($_.Exception.Message)"
    exit 1
}