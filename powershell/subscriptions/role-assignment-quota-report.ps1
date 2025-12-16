#!/usr/local/bin/pwsh

<#
.SYNOPSIS
    Azure Role Assignment Quota Report
.DESCRIPTION
    Checks for required PowerShell modules, installs missing components,
    and reports role assignment quota usage across Azure subscriptions.
.PARAMETER Subscriptions
    Comma-separated list of subscription IDs to check. If not provided, all subscriptions will be checked.
.PARAMETER Debug
    Enable debug output for detailed information
.EXAMPLE
    .\role-assignment-quota-report.ps1
.EXAMPLE
    .\role-assignment-quota-report.ps1 -Subscriptions "sub-id-1,sub-id-2"
.EXAMPLE
    $env:SUBSCRIPTIONS="sub-id-1,sub-id-2"; .\role-assignment-quota-report.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Subscriptions = $env:SUBSCRIPTIONS,
    
    [Parameter(Mandatory=$false)]
    [switch]$DebugMode = $($env:DEBUG -eq "1")
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Create temporary module directory
$tempModulePath = Join-Path ([System.IO.Path]::GetTempPath()) "AzurePSModules_$PID"
New-Item -ItemType Directory -Path $tempModulePath -Force | Out-Null

# Add temp path to PSModulePath for this session
$env:PSModulePath = "$tempModulePath$([IO.Path]::PathSeparator)$env:PSModulePath"

# Set HOME if it's empty (this fixes the Install-Module path issue)
if ([string]::IsNullOrEmpty($env:HOME)) {
    $env:HOME = [System.IO.Path]::GetTempPath()
}

#region Module Management

function Test-ModuleInstalled {
    param([string]$ModuleName)
    return (Get-Module -ListAvailable -Name $ModuleName) -ne $null
}

function Initialize-PowerShellEnvironment {
    Write-Host "🔧 Initializing PowerShell environment..." -ForegroundColor Cyan
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-Host "   PowerShell Version: $psVersion" -ForegroundColor Gray
    
    # Install NuGet provider if missing (required for module installation)
    Write-Host "📦 Checking NuGet package provider..." -ForegroundColor Cyan
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    
    if (-not $nuget) {
        Write-Host "   Installing NuGet package provider..." -ForegroundColor Yellow
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
            Write-Host "   ✅ NuGet provider installed" -ForegroundColor Green
        }
        catch {
            Write-Host "   ⚠️  Warning: Could not install NuGet provider: $_" -ForegroundColor Yellow
            Write-Host "   Attempting to continue..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   ✅ NuGet provider is available" -ForegroundColor Green
    }
    
    # Configure PowerShell Gallery as trusted repository
    Write-Host "📦 Configuring PowerShell Gallery..." -ForegroundColor Cyan
    $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    
    if ($psGallery) {
        if ($psGallery.InstallationPolicy -ne 'Trusted') {
            Write-Host "   Setting PSGallery as trusted repository..." -ForegroundColor Yellow
            try {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
                Write-Host "   ✅ PSGallery configured as trusted" -ForegroundColor Green
            }
            catch {
                Write-Host "   ⚠️  Warning: Could not set PSGallery as trusted: $_" -ForegroundColor Yellow
                Write-Host "   You may be prompted to confirm during module installation" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "   ✅ PSGallery is already trusted" -ForegroundColor Green
        }
    }
    else {
        Write-Host "   ⚠️  Warning: PSGallery repository not found" -ForegroundColor Yellow
        Write-Host "   Attempting to register PSGallery..." -ForegroundColor Yellow
        try {
            Register-PSRepository -Default -ErrorAction Stop
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            Write-Host "   ✅ PSGallery registered and configured" -ForegroundColor Green
        }
        catch {
            Write-Host "   ⚠️  Warning: Could not register PSGallery: $_" -ForegroundColor Yellow
        }
    }
    
    # Check for PowerShellGet and update if needed
    Write-Host "📦 Checking PowerShellGet..." -ForegroundColor Cyan
    $psGet = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
    
    if ($psGet) {
        Write-Host "   PowerShellGet version: $($psGet.Version)" -ForegroundColor Gray
        if ($psGet.Version -lt [version]"2.0.0") {
            Write-Host "   ⚠️  PowerShellGet is outdated. Attempting to update..." -ForegroundColor Yellow
            try {
                Install-Module -Name PowerShellGet -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-Host "   ✅ PowerShellGet updated. Please restart the script." -ForegroundColor Green
                Write-Host "   Note: A PowerShell restart may be required for changes to take effect." -ForegroundColor Yellow
                exit 0
            }
            catch {
                Write-Host "   ⚠️  Could not update PowerShellGet: $_" -ForegroundColor Yellow
                Write-Host "   Continuing with current version..." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "   ✅ PowerShellGet is up to date" -ForegroundColor Green
        }
    }
    else {
        Write-Host "   ❌ PowerShellGet not found" -ForegroundColor Red
        Write-Host "   Please install PowerShellGet: https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host ""
}

function Install-RequiredModule {
    param(
        [string]$ModuleName,
        [string]$MinimumVersion = $null
    )
    
    Write-Host "📦 Checking for module: $ModuleName..." -ForegroundColor Cyan
    
    if (Test-ModuleInstalled -ModuleName $ModuleName) {
        Write-Host "   ✅ Module $ModuleName is already installed" -ForegroundColor Green
        Import-Module $ModuleName -ErrorAction SilentlyContinue
        return
    }
    
    Write-Host "   ⚠️  Module $ModuleName not found. Installing..." -ForegroundColor Yellow
    
    try {
        # Determine installation scope
        if ($PSVersionTable.Platform -eq 'Win32NT' -or $null -eq $PSVersionTable.Platform) {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $scope = if ($isAdmin) { "AllUsers" } else { "CurrentUser" }
        } else {
            # For Linux/Mac, default to CurrentUser scope
            $scope = "CurrentUser"
        }
        
        Write-Host "   Installing to scope: $scope" -ForegroundColor Gray
        
        $installParams = @{
            Name = $ModuleName
            Scope = $scope
            Force = $true
            AllowClobber = $true
            SkipPublisherCheck = $true
        }
        
        if ($MinimumVersion) {
            $installParams.MinimumVersion = $MinimumVersion
        }
        
        Install-Module @installParams -ErrorAction Stop
        Import-Module $ModuleName -ErrorAction Stop
        Write-Host "   ✅ Successfully installed $ModuleName" -ForegroundColor Green
    }
    catch {
        Write-Host "   ❌ Failed to install $ModuleName" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "   Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "   1. Try manually: Install-Module $ModuleName -Scope CurrentUser -Force" -ForegroundColor Yellow
        Write-Host "   2. Check internet connectivity" -ForegroundColor Yellow
        Write-Host "   3. Verify PSGallery access: Find-Module $ModuleName" -ForegroundColor Yellow
        Write-Host "   4. Check PowerShell version: `$PSVersionTable" -ForegroundColor Yellow
        throw
    }
}

# Initialize PowerShell environment (NuGet, PSGallery, PowerShellGet)
Initialize-PowerShellEnvironment

# Install required Azure modules
Write-Host "📦 Checking required Azure modules..." -ForegroundColor Cyan
Write-Host ""

$requiredModules = @(
    @{ Name = "Az.Accounts"; MinVersion = "2.0.0" }
    @{ Name = "Az.Resources"; MinVersion = "6.0.0" }
    @{ Name = "Az.ResourceGraph"; MinVersion = "0.13.0" }
)

$installSuccess = $true
foreach ($module in $requiredModules) {
    try {
        Install-RequiredModule -ModuleName $module.Name -MinimumVersion $module.MinVersion
    }
    catch {
        $installSuccess = $false
        Write-Host ""
        Write-Host "❌ Failed to install required module: $($module.Name)" -ForegroundColor Red
        Write-Host "   Cannot continue without required modules." -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}

if ($installSuccess) {
    Write-Host ""
    Write-Host "✅ All required modules are installed and ready" -ForegroundColor Green
    Write-Host ""
}

#endregion

#region Azure Authentication

Write-Host "🔐 Checking Azure authentication status..." -ForegroundColor Cyan

try {
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Host "⚠️  Not logged in to Azure. Please authenticate..." -ForegroundColor Yellow
        Connect-AzAccount
        $context = Get-AzContext
    }
    
    Write-Host "✅ Authenticated as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Tenant: $($context.Tenant.Id)" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host "❌ Failed to authenticate to Azure: $_" -ForegroundColor Red
    exit 1
}

#endregion

#region Helper Functions

function Get-RoleAssignmentQuota {
    param([string]$SubscriptionId)
    
    try {
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleassignmentsusagemetrics?api-version=2019-08-01-preview"
        $result = Invoke-AzRestMethod -Uri $uri -Method GET
        
        if ($result.StatusCode -eq 200) {
            $content = $result.Content | ConvertFrom-Json
            return $content.roleAssignmentsLimit
        }
        else {
            if ($DebugMode) {
                Write-Host "  🔍 DEBUG: Failed to get quota limit, using default 2000" -ForegroundColor Gray
                Write-Host "  🔍 DEBUG: Status Code: $($result.StatusCode)" -ForegroundColor Gray
            }
            return 2000
        }
    }
    catch {
        if ($DebugMode) {
            Write-Host "  🔍 DEBUG: Exception getting quota limit: $_" -ForegroundColor Gray
        }
        return 2000
    }
}

function Get-RoleAssignmentCount {
    param([string]$SubscriptionId)
    
    try {
        $query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | where subscriptionId == '$SubscriptionId' | summarize count()"
        
        if ($DebugMode) {
            Write-Host "  🔍 DEBUG: Executing Resource Graph query" -ForegroundColor Gray
            Write-Host "  🔍 DEBUG: Query: $query" -ForegroundColor Gray
        }
        
        $result = Search-AzGraph -Query $query
        
        if ($result -and $result.count_ -ge 0) {
            if ($DebugMode) {
                Write-Host "  🔍 DEBUG: Query successful, count: $($result.count_)" -ForegroundColor Gray
            }
            return $result.count_
        }
        else {
            throw "No valid result returned from query"
        }
    }
    catch {
        if ($DebugMode) {
            Write-Host "  🔍 DEBUG: Exception during query: $_" -ForegroundColor Gray
        }
        throw
    }
}

#endregion

#region Main Logic

Write-Host "📊 Starting Role Assignment Quota Report" -ForegroundColor Cyan
Write-Host ""

# Determine which subscriptions to check
if ([string]::IsNullOrWhiteSpace($Subscriptions)) {
    Write-Host "📋 Retrieving all accessible subscriptions..." -ForegroundColor Cyan
    $subscriptionList = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
}
else {
    Write-Host "📋 Using provided subscription list..." -ForegroundColor Cyan
    $subIds = $Subscriptions -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $subscriptionList = $subIds | ForEach-Object {
        try {
            Get-AzSubscription -SubscriptionId $_.Trim() -ErrorAction Stop
        }
        catch {
            Write-Host "⚠️  Warning: Could not access subscription $_" -ForegroundColor Yellow
        }
    }
}

Write-Host "Found $($subscriptionList.Count) subscription(s) to check" -ForegroundColor Cyan
Write-Host ""

# Process each subscription
foreach ($sub in $subscriptionList) {
    Write-Host "Checking subscription: $($sub.Name) ($($sub.Id))" -ForegroundColor White
    
    try {
        # Set context to the subscription
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        
        # Get quota limit
        $quotaLimit = Get-RoleAssignmentQuota -SubscriptionId $sub.Id
        
        # Get role assignment count
        $count = Get-RoleAssignmentCount -SubscriptionId $sub.Id
        
        Write-Host "  Role assignments used: $count" -ForegroundColor White
        Write-Host "  Current quota limit:   $quotaLimit" -ForegroundColor White
        
        # Determine status
        if ($count -eq 0) {
            Write-Host "  ⚠️  No role assignments found - this may indicate an access issue or unusual configuration." -ForegroundColor Yellow
        }
        elseif ($count -ge $quotaLimit) {
            Write-Host "  ⚠️  Quota limit reached or exceeded!" -ForegroundColor Red
        }
        elseif ($count -ge ($quotaLimit * 0.9)) {
            Write-Host "  ⚠️  Usage is above 90% of the quota!" -ForegroundColor Yellow
        }
        else {
            Write-Host "  ✅ Within safe quota range." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ❌ Error retrieving role assignment count." -ForegroundColor Red
        Write-Host "  Message: $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "✅ Report complete!" -ForegroundColor Green

#endregion

