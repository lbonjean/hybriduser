#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup Azure AD Cloud Sync for one-way synchronization (AD to Entra ID)
.DESCRIPTION
    Creates a new Cloud Sync job configuration for syncing users from on-premises AD to Entra ID only
.EXAMPLE
    .\setup-cloudsync.ps1 -DomainName "contoso.local" -TargetOU "OU=CloudUsers,DC=contoso,DC=local"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "",
    
    [Parameter(Mandatory=$false)]
    [string]$JobName = "CloudSync-OneWay-$(Get-Date -Format 'yyyyMMdd')"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure AD Cloud Sync Setup (One-Way)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Domain: $DomainName" -ForegroundColor White
Write-Host "Target OU: $(if($TargetOU) { $TargetOU } else { 'All Users' })" -ForegroundColor White
Write-Host "Job Name: $JobName" -ForegroundColor White
Write-Host ""

# Step 1: Find Cloud Sync Service Principal
Write-Host "1. Finding Cloud Sync Service Principal..." -ForegroundColor Yellow
$syncServiceId = az ad sp list --query "[?contains(displayName,'Synchronization')].id" --output tsv | Select-Object -First 1

if (-not $syncServiceId) {
    Write-Host "✗ Cloud Sync Service Principal not found. Is the agent registered?" -ForegroundColor Red
    exit 1
}

Write-Host "  Service Principal ID: $syncServiceId" -ForegroundColor Green
Write-Host ""

# Step 2: Get available templates
Write-Host "2. Getting synchronization templates..." -ForegroundColor Yellow
$templates = az rest --method GET --url "https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/templates" | ConvertFrom-Json

if (-not $templates.value) {
    Write-Host "✗ No synchronization templates found" -ForegroundColor Red
    exit 1
}

# Find the AD to Azure AD template (usually for Cloud Sync)
$adTemplate = $templates.value | Where-Object { $_.title -like "*Active Directory*" -and $_.title -like "*Azure*" } | Select-Object -First 1

if (-not $adTemplate) {
    Write-Host "Available templates:" -ForegroundColor Yellow
    $templates.value | ForEach-Object { Write-Host "  - $($_.title) ($($_.id))" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "✗ AD to Azure AD template not found" -ForegroundColor Red
    exit 1
}

Write-Host "  Using template: $($adTemplate.title)" -ForegroundColor Green
Write-Host "  Template ID: $($adTemplate.id)" -ForegroundColor Green
Write-Host ""

# Step 3: Create sync job configuration
Write-Host "3. Creating synchronization job..." -ForegroundColor Yellow

$jobConfig = @{
    templateId = $adTemplate.id
} | ConvertTo-Json

# Create temp file for job config
$tempFile = [System.IO.Path]::GetTempFileName()
$jobConfig | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline

try {
    $newJob = az rest --method POST --url "https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/jobs" --body "@$tempFile" | ConvertFrom-Json
    
    Write-Host "  ✓ Sync job created: $($newJob.id)" -ForegroundColor Green
    $jobId = $newJob.id
}
catch {
    Write-Host "✗ Failed to create sync job: $_" -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

Write-Host ""

# Step 4: Configure sync scope (one-way only)
Write-Host "4. Configuring synchronization scope..." -ForegroundColor Yellow

# Get current schema
$schema = az rest --method GET --url "https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/jobs/$jobId/schema" | ConvertFrom-Json

# Configure for one-way sync (AD -> Azure AD only)
$schema.synchronizationRules = $schema.synchronizationRules | Where-Object { $_.direction -eq "Inbound" }

# If TargetOU is specified, add filtering
if ($TargetOU) {
    foreach ($rule in $schema.synchronizationRules) {
        if ($rule.sourceDirectoryName -eq "Active Directory") {
            $rule.containerFilter = @{
                includedContainers = @($TargetOU)
            }
        }
    }
}

# Save schema configuration
$schemaJson = $schema | ConvertTo-Json -Depth 10
$tempSchemaFile = [System.IO.Path]::GetTempFileName()
$schemaJson | Out-File -FilePath $tempSchemaFile -Encoding utf8 -NoNewline

try {
    az rest --method PUT --url "https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/jobs/$jobId/schema" --body "@$tempSchemaFile" | Out-Null
    Write-Host "  ✓ Schema configured for one-way sync" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to configure schema: $_" -ForegroundColor Red
}
finally {
    Remove-Item $tempSchemaFile -ErrorAction SilentlyContinue
}

Write-Host ""

# Step 5: Start the synchronization job
Write-Host "5. Starting synchronization job..." -ForegroundColor Yellow

try {
    az rest --method POST --url "https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/jobs/$jobId/start" | Out-Null
    Write-Host "  ✓ Synchronization job started" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to start sync job: $_" -ForegroundColor Red
}

Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Job ID: $jobId" -ForegroundColor White
Write-Host "Direction: One-way (AD → Entra ID)" -ForegroundColor White
Write-Host "Domain: $DomainName" -ForegroundColor White

if ($TargetOU) {
    Write-Host "Scope: $TargetOU" -ForegroundColor White
} else {
    Write-Host "Scope: All users" -ForegroundColor White
}

Write-Host ""
Write-Host "Monitor sync status with:" -ForegroundColor Yellow
Write-Host "  az rest --method GET --url 'https://graph.microsoft.com/beta/servicePrincipals/$syncServiceId/synchronization/jobs/$jobId'" -ForegroundColor Gray
Write-Host ""