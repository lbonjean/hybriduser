# Test SCIM Bulk Upload API
# This script tests the inbound provisioning API manually

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserId = "53453e32-55f4-425c-805c-ea30d072de7a"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test SCIM Bulk Upload API" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the provisioning API endpoint from parameters file
Write-Host "Loading configuration..." -ForegroundColor Yellow
$params = Get-Content "main.parameters.json" | ConvertFrom-Json
$apiEndpoint = $params.parameters.provisioningApiEndpoint.value

Write-Host "  API Endpoint: $apiEndpoint" -ForegroundColor White
Write-Host "  Test User ID: $UserId" -ForegroundColor White
Write-Host ""

# Get user details from Microsoft Graph
Write-Host "Fetching user details from Microsoft Graph..." -ForegroundColor Yellow
try {
    $userJson = az rest --method GET `
        --uri "https://graph.microsoft.com/v1.0/users/$UserId`?`$select=id,userPrincipalName,displayName,givenName,surname,mail,mailNickname,jobTitle,department,companyName,businessPhones,mobilePhone,preferredLanguage,usageLocation,employeeId,city,country,postalCode,state,streetAddress,officeLocation" `
        --headers "ConsistencyLevel=eventual"
    
    $user = $userJson | ConvertFrom-Json
    
    Write-Host "  User: $($user.displayName) ($($user.userPrincipalName))" -ForegroundColor Green
    if ($user.employeeId) {
        Write-Host "  EmployeeId: $($user.employeeId)" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "✗ Failed to fetch user: $_" -ForegroundColor Red
    exit 1
}

# Build SCIM Bulk Request payload
Write-Host ""
Write-Host "Building SCIM Bulk Request payload..." -ForegroundColor Yellow

# Determine externalId: use employeeId if available, otherwise use timestamp
$externalId = if ($user.employeeId) { 
    $user.employeeId 
} else { 
    Get-Date -Format 'yyyyMMddHHmmss' 
}

Write-Host "  ExternalId strategy: $(if ($user.employeeId) { 'Using employeeId' } else { 'Using timestamp (no employeeId found)' })" -ForegroundColor Cyan
Write-Host "  ExternalId value: $externalId" -ForegroundColor White

# Build phone numbers array (only include non-empty values)
$phoneNumbers = @()
if ($user.businessPhones -and $user.businessPhones.Count -gt 0) {
    $phoneNumbers += @{
        value = $user.businessPhones[0]
        type = "work"
    }
}
if ($user.mobilePhone) {
    $phoneNumbers += @{
        value = $user.mobilePhone
        type = "mobile"
    }
}

# Build address (only if at least one field is filled)
$hasAddress = $user.streetAddress -or $user.city -or $user.postalCode -or $user.state -or $user.country
$addresses = @()
if ($hasAddress) {
    $addresses += @{
        type = "work"
        streetAddress = $user.streetAddress
        locality = $user.city
        postalCode = $user.postalCode
        region = $user.state
        country = $user.country
    }
}

# Build Enterprise User extension
$enterpriseUser = @{}
if ($user.employeeId) {
    $enterpriseUser.employeeNumber = $user.employeeId
}
if ($user.department) {
    $enterpriseUser.department = $user.department
}
if ($user.companyName) {
    $enterpriseUser.organization = $user.companyName
}

$scimData = @{
    schemas = @(
        "urn:ietf:params:scim:schemas:core:2.0:User"
        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
    )
    externalId = $externalId
    userName = $user.userPrincipalName
    name = @{
        givenName = $user.givenName
        familyName = $user.surname
    }
    displayName = $user.displayName
    emails = @(
        @{
            value = if ($user.mail) { $user.mail } else { $user.userPrincipalName }
            type = "work"
            primary = $true
        }
    )
    active = $true
}

# Add optional fields only if they have values
if ($user.mailNickname) {
    $scimData.nickName = $user.mailNickname
}
if ($user.jobTitle) {
    $scimData.title = $user.jobTitle
}
if ($user.preferredLanguage) {
    $scimData.preferredLanguage = $user.preferredLanguage
}
if ($user.usageLocation) {
    $scimData.locale = $user.usageLocation
}
if ($phoneNumbers.Count -gt 0) {
    $scimData.phoneNumbers = $phoneNumbers
}
if ($addresses.Count -gt 0) {
    $scimData.addresses = $addresses
}

# Add Enterprise User extension
$scimData."urn:ietf:params:scim:schemas:extension:enterprise:2.0:User" = $enterpriseUser

$scimPayload = @{
    schemas = @(
        "urn:ietf:params:scim:api:messages:2.0:BulkRequest"
    )
    Operations = @(
        @{
            method = "POST"
            bulkId = [System.Guid]::NewGuid().ToString()
            path = "/Users"
            data = $scimData
        }
    )
    failOnErrors = $null
}

$payloadJson = $scimPayload | ConvertTo-Json -Depth 10
Write-Host "  Payload size: $($payloadJson.Length) bytes" -ForegroundColor White

# Save payload to file for inspection
$payloadFile = "scim-test-payload.json"
$payloadJson | Out-File -FilePath $payloadFile -Encoding UTF8
Write-Host "  Saved to: $payloadFile" -ForegroundColor White

# Display the payload
Write-Host ""
Write-Host "SCIM Payload:" -ForegroundColor Cyan
Write-Host $payloadJson -ForegroundColor Gray

# Ask for confirmation
Write-Host ""
$confirm = Read-Host "Do you want to send this payload to the API? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# Send request to provisioning API
Write-Host ""
Write-Host "Sending request to provisioning API..." -ForegroundColor Yellow
Write-Host "  Endpoint: $apiEndpoint" -ForegroundColor White

try {
    $response = az rest --method POST `
        --uri $apiEndpoint `
        --headers "Content-Type=application/scim+json" `
        --body "@$payloadFile"
    
    Write-Host ""
    Write-Host "✓ Request sent successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Response:" -ForegroundColor Cyan
    Write-Host $response -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "✗ Request failed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host $_ -ForegroundColor Red
    
    # Check for common issues
    Write-Host ""
    Write-Host "Common issues to check:" -ForegroundColor Yellow
    Write-Host "  1. Managed Identity has Synchronization.ReadWrite.All permission" -ForegroundColor White
    Write-Host "  2. API endpoint is correct (check servicePrincipal ID and job ID)" -ForegroundColor White
    Write-Host "  3. Content-Type header is 'application/scim+json'" -ForegroundColor White
    Write-Host "  4. SCIM payload format matches the specification" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Check provisioning logs in Azure Portal" -ForegroundColor White
Write-Host "  2. Verify user was created in AD DS" -ForegroundColor White
Write-Host "  3. If successful, the Logic App should work with the same payload" -ForegroundColor White
Write-Host ""
