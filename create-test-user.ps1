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

Write-Host "Creating test user..." -ForegroundColor Cyan
Write-Host "  Display Name: $displayName" -ForegroundColor Gray
Write-Host "  UPN: $userPrincipalName" -ForegroundColor Gray
Write-Host "  Password: $password" -ForegroundColor Yellow

# Create the user
try {
    $user = az ad user create `
        --display-name $displayName `
        --user-principal-name $userPrincipalName `
        --password $password `
        --mail-nickname $userName `
        --force-change-password-next-sign-in false | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create user"
    }
    
    $userId = $user.id
    Write-Host "✅ User created with ID: $userId" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create user: $_"
    exit 1
}

# Get the admin unit ID
Write-Host "`nFinding admin unit '$AdminUnitName'..." -ForegroundColor Cyan
try {
    $adminUnits = az rest `
        --method GET `
        --uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits?`$filter=displayName eq '$AdminUnitName'" | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query admin units"
    }
    
    if ($adminUnits.value.Count -eq 0) {
        Write-Warning "Admin unit '$AdminUnitName' not found. User created but not added to admin unit."
        Write-Host "`nUser Details:" -ForegroundColor Yellow
        Write-Host "  ID: $userId"
        Write-Host "  UPN: $userPrincipalName"
        Write-Host "  Password: $password"
        exit 0
    }
    
    $adminUnitId = $adminUnits.value[0].id
    Write-Host "✅ Admin unit found: $adminUnitId" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to find admin unit: $_"
    Write-Host "`nUser Details:" -ForegroundColor Yellow
    Write-Host "  ID: $userId"
    Write-Host "  UPN: $userPrincipalName"
    Write-Host "  Password: $password"
    exit 1
}

# Add user to admin unit
Write-Host "`nAdding user to admin unit..." -ForegroundColor Cyan
try {
    # Use temp file to avoid escaping issues
    $tempFile = [System.IO.Path]::GetTempFileName()
    @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/users/$userId"
    } | ConvertTo-Json | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline
    
    $result = az rest `
        --method POST `
        --uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$adminUnitId/members/`$ref" `
        --body "@$tempFile" `
        --headers "Content-Type=application/json" 2>&1
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add user to admin unit: $result"
    }
    
    Write-Host "✅ User added to admin unit" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to add user to admin unit: $_"
    Write-Host "`nUser created but not in admin unit. You may need to add manually." -ForegroundColor Yellow
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
