#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates a test user in Azure AD for Logic App testing
.DESCRIPTION
    Creates a test user with timestamp in name and GUID password, 
    then adds them to the hybrid user admin unit
.EXAMPLE
    .\create-test-user.ps1
#>

param(
    [string]$AdminUnitName = "Hybrid",
    [string]$Domain = "@bas-services.nl"
)

# Generate timestamp and unique values
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$userName = "test-$timestamp"
$displayName = "Test User $timestamp"
$userPrincipalName = "$userName$Domain"
$password = (New-Guid).ToString()

# Get the admin unit ID first
Write-Host "Finding admin unit '$AdminUnitName'..." -ForegroundColor Cyan
try {
    $adminUnits = az rest `
        --method GET `
        --uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits?`$filter=displayName eq '$AdminUnitName'" | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query admin units"
    }
    
    if ($adminUnits.value.Count -eq 0) {
        Write-Error "Admin unit '$AdminUnitName' not found. Cannot create user without admin unit."
        exit 1
    }
    
    $adminUnitId = $adminUnits.value[0].id
    Write-Host "✅ Admin unit found: $adminUnitId" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to find admin unit: $_"
    exit 1
}

# Create the user directly in the admin unit via Graph API
Write-Host "`nCreating test user in admin unit..." -ForegroundColor Cyan
Write-Host "  Display Name: $displayName" -ForegroundColor Gray
Write-Host "  UPN: $userPrincipalName" -ForegroundColor Gray
Write-Host "  Password: $password" -ForegroundColor Yellow

try {
    # Use temp file to avoid escaping issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    @{
        accountEnabled = $true
        displayName = $displayName
        mailNickname = $userName
        userPrincipalName = $userPrincipalName
        passwordProfile = @{
            forceChangePasswordNextSignIn = $false
            password = $password
        }
    } | ConvertTo-Json | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
    
    $user = az rest `
        --method POST `
        --uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$adminUnitId/members" `
        --body "@$tempFile" `
        --headers "Content-Type=application/json" | ConvertFrom-Json
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create user in admin unit"
    }
    
    $userId = $user.id
    Write-Host "✅ User created in admin unit with ID: $userId" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create user in admin unit: $_"
    exit 1
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test User Created Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "User ID:       $userId" -ForegroundColor White
Write-Host "UPN:           $userPrincipalName" -ForegroundColor White
Write-Host "Display Name:  $displayName" -ForegroundColor White
Write-Host "Password:      $password" -ForegroundColor Yellow
Write-Host "Admin Unit:    $AdminUnitName" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`n💡 The Logic App should trigger within a few minutes to process this user." -ForegroundColor Cyan
