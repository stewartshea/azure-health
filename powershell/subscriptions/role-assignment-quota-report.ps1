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

#region Module Management

function Test-ModuleInstalled {
    param([string]$ModuleName)
    return (Get-Module -ListAvailable -Name $ModuleName) -ne $null
}

function Install-RequiredModule {
    param(
        [string]$ModuleName,
        [string]$MinimumVersion = $null
    )
    
    Write-Host "📦 Checking for module: $ModuleName..." -ForegroundColor Cyan
    
    if (Test-ModuleInstalled -ModuleName $ModuleName) {
        Write-Host "✅ Module $ModuleName is already installed" -ForegroundColor Green
        Import-Module $ModuleName -ErrorAction SilentlyContinue
        return
    }
    
    Write-Host "⚠️  Module $ModuleName not found. Installing..." -ForegroundColor Yellow
    
    try {
        # Check if running as administrator (Windows) or with appropriate permissions
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
        }
        
        if ($MinimumVersion) {
            $installParams.MinimumVersion = $MinimumVersion
        }
        
        Install-Module @installParams -ErrorAction Stop
        Import-Module $ModuleName -ErrorAction Stop
        Write-Host "✅ Successfully installed $ModuleName" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to install $ModuleName : $_" -ForegroundColor Red
        Write-Host "   You may need to run: Install-Module $ModuleName -Scope CurrentUser -Force" -ForegroundColor Yellow
        throw
    }
}

Write-Host "🔧 Checking and installing required modules..." -ForegroundColor Cyan
Write-Host ""

# Check for PowerShellGet (needed for module installation)
if (-not (Test-ModuleInstalled -ModuleName "PowerShellGet")) {
    Write-Host "⚠️  PowerShellGet not found. This is required for module installation." -ForegroundColor Yellow
    Write-Host "   Please install PowerShellGet first: https://docs.microsoft.com/en-us/powershell/scripting/gallery/installing-psget" -ForegroundColor Yellow
    exit 1
}

# Install required Azure modules
$requiredModules = @(
    @{ Name = "Az.Accounts"; MinVersion = "2.0.0" }
    @{ Name = "Az.Resources"; MinVersion = "6.0.0" }
    @{ Name = "Az.ResourceGraph"; MinVersion = "0.13.0" }
)

foreach ($module in $requiredModules) {
    Install-RequiredModule -ModuleName $module.Name -MinimumVersion $module.MinVersion
}

Write-Host ""

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

