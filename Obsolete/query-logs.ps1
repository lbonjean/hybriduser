# Monitoring and Query Helper Script
# This script provides useful queries for monitoring the Hybrid User Sync solution

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Events", "Errors", "Provisioning", "Renewals", "Summary", "Heartbeat")]
    [string]$QueryType = "Summary",
    
    [Parameter(Mandatory = $false)]
    [int]$Hours = 24
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Hybrid User Sync - Monitoring" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Resolve workspace ID if name is provided
if ($WorkspaceName -and -not $WorkspaceId) {
    if (-not $ResourceGroupName) {
        Write-Host "✗ ResourceGroupName is required when using WorkspaceName" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Resolving workspace ID from name..." -ForegroundColor Yellow
    try {
        $workspace = Get-AzOperationalInsightsWorkspace `
            -ResourceGroupName $ResourceGroupName `
            -Name $WorkspaceName `
            -ErrorAction Stop
        
        $WorkspaceId = $workspace.CustomerId
        Write-Host "✓ Workspace ID: $WorkspaceId" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to find workspace: $_" -ForegroundColor Red
        exit 1
    }
}

if (-not $WorkspaceId) {
    Write-Host "✗ Either WorkspaceId or WorkspaceName (with ResourceGroupName) must be provided" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Check if Az.OperationalInsights module is installed
if (-not (Get-Module -ListAvailable -Name Az.OperationalInsights)) {
    Write-Host "Installing Az.OperationalInsights module..." -ForegroundColor Yellow
    Install-Module Az.OperationalInsights -Scope CurrentUser -Force
}

# Define queries
$queries = @{
    Summary      = @"
HybridUserSync_CL
| where TimeGenerated > ago($($Hours)h)
| summarize Count = count() by EventType_s
| order by Count desc
"@
    Events       = @"
HybridUserSync_CL
| where TimeGenerated > ago($($Hours)h)
| order by TimeGenerated desc
| project TimeGenerated, EventType_s, UserPrincipalName_s, UserId_s
"@
    Errors       = @"
HybridUserSync_CL
| where TimeGenerated > ago($($Hours)h)
| where EventType_s == "ProcessingError"
| order by TimeGenerated desc
| project TimeGenerated, UserId_s, Error_s
"@
    Provisioning = @"
HybridUserSync_CL
| where TimeGenerated > ago($($Hours)h)
| where EventType_s in ("ProvisioningStarted", "ProvisioningSuccess")
| order by TimeGenerated desc
| project TimeGenerated, EventType_s, UserPrincipalName_s, UserId_s
"@
    Renewals     = @"
HybridUserSync_CL
| where TimeGenerated > ago($($Hours)h)
| where EventType_s in ("SubscriptionRenewalSuccess", "SubscriptionRenewalFailure", "CreatingNewSubscription")
| order by TimeGenerated desc
| project TimeGenerated, EventType_s, SubscriptionId_s, NewExpiration_s, Action_s
"@
    Heartbeat    = @"
HybridUserSync_CL
| where EventType_s == "SubscriptionRenewalSuccess"
| summarize LastRenewal = max(TimeGenerated)
| extend HoursSinceLastRenewal = datetime_diff('hour', now(), LastRenewal)
| extend Status = iff(HoursSinceLastRenewal > 60, "ALERT", "OK")
"@
}

Write-Host "Query Type: $QueryType" -ForegroundColor Yellow
Write-Host "Time Range: Last $Hours hours" -ForegroundColor Yellow
Write-Host "Workspace ID: $WorkspaceId" -ForegroundColor Gray
Write-Host ""

$query = $queries[$QueryType]

Write-Host "Executing query..." -ForegroundColor Yellow
Write-Host ""
Write-Host $query -ForegroundColor Gray
Write-Host ""

try {
    $result = Invoke-AzOperationalInsightsQuery `
        -WorkspaceId $WorkspaceId `
        -Query $query
    
    if ($result.Results.Count -eq 0) {
        Write-Host "No results found" -ForegroundColor Yellow
    }
    else {
        Write-Host "Results:" -ForegroundColor Green
        $result.Results | Format-Table -AutoSize
        Write-Host ""
        Write-Host "Total rows: $($result.Results.Count)" -ForegroundColor Gray
    }
}
catch {
    Write-Host "✗ Query failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Additional info based on query type
switch ($QueryType) {
    "Heartbeat" {
        $lastRenewal = $result.Results[0]
        if ($lastRenewal.Status -eq "ALERT") {
            Write-Host "⚠ WARNING: No renewal in the last 60 hours!" -ForegroundColor Red
            Write-Host "  Last renewal: $($lastRenewal.LastRenewal)" -ForegroundColor Yellow
            Write-Host "  Hours since: $($lastRenewal.HoursSinceLastRenewal)" -ForegroundColor Yellow
        }
        else {
            Write-Host "✓ Heartbeat OK" -ForegroundColor Green
            Write-Host "  Last renewal: $($lastRenewal.LastRenewal)" -ForegroundColor White
            Write-Host "  Hours since: $($lastRenewal.HoursSinceLastRenewal)" -ForegroundColor White
        }
    }
    "Errors" {
        if ($result.Results.Count -gt 0) {
            Write-Host "⚠ Found $($result.Results.Count) error(s)" -ForegroundColor Yellow
            Write-Host "  Check dead letter storage for details" -ForegroundColor Gray
        }
        else {
            Write-Host "✓ No errors found" -ForegroundColor Green
        }
    }
}

Write-Host ""
