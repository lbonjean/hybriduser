param(
    [Parameter(Mandatory=$true)]
    [string]$PrincipalId
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Grant Graph Permissions to Managed Identity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Microsoft Graph Service Principal
$graphAppId = "00000003-0000-0000-c000-000000000000"

# Get Graph Service Principal
Write-Host "Getting Microsoft Graph service principal..." -ForegroundColor Yellow
$graphSpJson = az ad sp show --id $graphAppId --query '{id:id,appRoles:appRoles}'
$graphSp = $graphSpJson | ConvertFrom-Json

Write-Host "  Microsoft Graph SP ID: $($graphSp.id)" -ForegroundColor White
Write-Host ""

# Permissions to grant
$permissionsToGrant = @(
    "User.Read.All",
    "AdministrativeUnit.Read.All", 
    "Directory.ReadWrite.All",
    "Synchronization.ReadWrite.All"
)

Write-Host "Granting permissions to principal: $PrincipalId" -ForegroundColor Yellow
Write-Host ""

foreach ($permName in $permissionsToGrant) {
    Write-Host "  $permName..." -ForegroundColor Cyan
    
    # Find the app role
    $appRole = $graphSp.appRoles | Where-Object { $_.value -eq $permName } | Select-Object -First 1
    
    if (-not $appRole) {
        Write-Host "    ✗ App role not found!" -ForegroundColor Red
        continue
    }
    
    Write-Host "    App Role ID: $($appRole.id)" -ForegroundColor Gray
    
    # Grant permission using REST API
    $body = "{`"principalId`":`"$PrincipalId`",`"resourceId`":`"$($graphSp.id)`",`"appRoleId`":`"$($appRole.id)`"}"
    
    $result = az rest --method POST `
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
        --headers "Content-Type=application/json" `
        --body $body `
        2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ Granted" -ForegroundColor Green
    } elseif ($result -match "already exists|Conflict|Permission being assigned already exists") {
        Write-Host "    ✓ Already granted" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Failed" -ForegroundColor Red
        Write-Host "    Error: $result" -ForegroundColor Gray
    }
    
    Write-Host ""
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
