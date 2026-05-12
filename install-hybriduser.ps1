    param (
    [Parameter()]
    [string]
    $resourceGroup,
    [string]
    $location,
    [string]
    $namePrefix,
    [string]
    $provisioningApiEndpoint,
    [string]
    $adminUnitId

)
<# 
Example usage:
./install-hybriduser.ps1 -resourceGroup C0089-hybriduser-rg -namePrefix C0089 -location northeurope -adminUnitId 1d1c8021-04ab-4015-a2b7-5aa5d8599b4d -provisioningApiEndpoint "https://graph.microsoft.com/v1.0/servicePrincipals/7c1305ba-d291-4d86-8612-ea6809db8b18/synchronization/jobs/API2AD.f8b0f1b26abf433f8786597a6821a59c.b067346d-20bc-4b2f-b382-99abd375ade0/bulkUpload"
 #>

# Validate that the administrative unit exists in Entra ID
Write-Host "Checking if Entra ID administrative unit exists: $adminUnitId" -ForegroundColor Cyan

$adminUnitCheck = az rest --method GET --uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$adminUnitId" --headers "Content-Type=application/json" 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0 -or $adminUnitCheck -like "*error*") {
    Write-Host "ERROR: Administrative unit validation failed!" -ForegroundColor Red
    Write-Host "Details: $adminUnitCheck" -ForegroundColor Red
    Write-Host "`nPlease verify:" -ForegroundColor Yellow
    Write-Host "  1. The admin unit ID is correct (should be a valid GUID)"
    Write-Host "  2. You are logged in with 'az login'"
    Write-Host "  3. You have permissions to read administrative units"
    exit 1
}

try {
    $adminUnit = $adminUnitCheck | ConvertFrom-Json
    
    if ($null -eq $adminUnit.id) {
        Write-Host "ERROR: Administrative unit not found with ID: $adminUnitId" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Administrative unit found: $($adminUnit.displayName)" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to parse administrative unit response." -ForegroundColor Red
    Write-Host "Error details: $_" -ForegroundColor Red
    exit 1
}

az group create --name $resourceGroup --location $location
#$result= az deployment group create --resource-group $resourceGroup --template-file main.bicep --parameters namePrefix=$namePrefix | ConvertFrom-Json
$result=(az deployment group create --name "hybrid-user-$(get-date -Format 'yyyyMMddHHmmss')" --resource-group $resourceGroup --template-file main.bicep --parameters namePrefix=$namePrefix adminUnitId=$adminUnitId provisioningApiEndpoint=$provisioningApiEndpoint --query properties.outputs | convertfrom-json)
write-host "Deployed resources with the following outputs:"
$result | Format-List

./grant-system-identity-permissions.ps1 -principalId $result.logicAppPrincipalId.value
./grant-system-identity-permissions.ps1 -principalId $result.renewalLogicAppPrincipalId.value