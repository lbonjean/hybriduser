# Get Provisioning Logs
# This script queries the provisioning logs from the audit API

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Top = 5
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Get Provisioning Logs" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get the service principal ID from parameters
$params = Get-Content "main.parameters.json" | ConvertFrom-Json
$apiEndpoint = $params.parameters.provisioningApiEndpoint.value

# Extract service principal ID from endpoint
if ($apiEndpoint -match "servicePrincipals/([a-f0-9-]+)/") {
    $spId = $Matches[1]
} else {
    Write-Host "✗ Could not extract service principal ID from endpoint" -ForegroundColor Red
    exit 1
}

Write-Host "Service Principal ID: $spId" -ForegroundColor White
Write-Host "Fetching last $Top provisioning logs..." -ForegroundColor Yellow
Write-Host ""

try {
    $logsJson = az rest --method GET `
        --uri "https://graph.microsoft.com/beta/auditLogs/provisioning?`$filter=servicePrincipal/id eq '$spId'&`$top=$Top&`$orderby=activityDateTime desc"
    
    $logs = $logsJson | ConvertFrom-Json
    
    Write-Host "Found $($logs.value.Count) log entries" -ForegroundColor Green
    Write-Host ""
    
    foreach ($log in $logs.value) {
        $status = $log.provisioningStatusInfo.status
        $statusColor = if ($status -eq "success") { "Green" } else { "Red" }
        $statusSymbol = if ($status -eq "success") { "✓" } else { "✗" }
        
        Write-Host "$statusSymbol $($log.activityDateTime) - $($log.action)" -ForegroundColor $statusColor
        Write-Host "  ExternalId: $($log.sourceIdentity.id)" -ForegroundColor White
        Write-Host "  User: $($log.provisioningSteps[0].details.displayName)" -ForegroundColor White
        
        if ($status -eq "success") {
            # Show created user details
            $exportStep = $log.provisioningSteps | Where-Object { $_.name -eq "EntryExportAdd" }
            if ($exportStep -and $exportStep.details) {
                Write-Host "  AD User:" -ForegroundColor Cyan
                Write-Host "    sAMAccountName: $($exportStep.details.sAMAccountName)" -ForegroundColor Gray
                Write-Host "    employeeID: $($exportStep.details.employeeID)" -ForegroundColor Gray
                Write-Host "    DN: $($exportStep.details.parentDistinguishedName)" -ForegroundColor Gray
            }
        } else {
            # Show error
            $error = $log.provisioningStatusInfo.errorInformation
            if ($error) {
                Write-Host "  Error: $($error.errorCode)" -ForegroundColor Red
                Write-Host "  Reason: $($error.reason.Substring(0, [Math]::Min(100, $error.reason.Length)))..." -ForegroundColor Red
            }
        }
        
        Write-Host ""
    }
    
    # Summary
    $successCount = ($logs.value | Where-Object { $_.provisioningStatusInfo.status -eq "success" }).Count
    $failureCount = ($logs.value | Where-Object { $_.provisioningStatusInfo.status -eq "failure" }).Count
    
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Successes: $successCount" -ForegroundColor Green
    Write-Host "  Failures: $failureCount" -ForegroundColor Red
}
catch {
    Write-Host "✗ Failed to fetch logs: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
