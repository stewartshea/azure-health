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

# Set environment variables for PowerShell path resolution
# Use CODEBUNDLE_TEMP_DIR if available, otherwise use temp path
$basePath = if (-not [string]::IsNullOrEmpty($env:CODEBUNDLE_TEMP_DIR)) {
    $env:CODEBUNDLE_TEMP_DIR
} else {
    [System.IO.Path]::GetTempPath()
}

# Set HOME (required for module path resolution on Linux/Mac)
if ([string]::IsNullOrEmpty($env:HOME)) {
    $env:HOME = $basePath
}

# Create expected PowerShell directory structure under HOME
# This helps PowerShellGet resolve paths correctly
$psUserModulesPath = if ($IsWindows -or $PSVersionTable.Platform -eq 'Win32NT' -or $null -eq $PSVersionTable.Platform) {
    Join-Path $env:HOME "Documents\PowerShell\Modules"
} else {
    Join-Path $env:HOME ".local/share/powershell/Modules"
}
New-Item -ItemType Directory -Path $psUserModulesPath -Force | Out-Null

# Set USERPROFILE (Windows equivalent, PowerShell may check this)
if ([string]::IsNullOrEmpty($env:USERPROFILE)) {
    $env:USERPROFILE = $basePath
}

# Set TMP/TEMP if not set (used for temporary files during module operations)
if ([string]::IsNullOrEmpty($env:TMP)) {
    $env:TMP = $basePath
}
if ([string]::IsNullOrEmpty($env:TEMP)) {
    $env:TEMP = $basePath
}

# Set USER/USERNAME if not set (some module operations may check this)
if ([string]::IsNullOrEmpty($env:USER) -and [string]::IsNullOrEmpty($env:USERNAME)) {
    $env:USER = "pwsh-user"
    $env:USERNAME = "pwsh-user"
}

# Set PATH if not set (required for many operations)
if ([string]::IsNullOrEmpty($env:PATH)) {
    $env:PATH = "/usr/local/bin:/usr/bin:/bin"
}
else {
    # Ensure temp path is in PATH
    if ($env:PATH -notlike "*$basePath*") {
        $env:PATH = "$basePath:$env:PATH"
    }
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
        try {
            Import-Module $ModuleName -Force -ErrorAction Stop
        }
        catch {
            Write-Host "   ⚠️  Warning: Could not import $ModuleName, will retry later: $_" -ForegroundColor Yellow
        }
        return
    }
    
    Write-Host "   ⚠️  Module $ModuleName not found. Installing..." -ForegroundColor Yellow
    
    try {
        # Ensure temp path is absolute and exists
        $absoluteTempPath = [System.IO.Path]::GetFullPath($tempModulePath)
        if (-not (Test-Path $absoluteTempPath)) {
            New-Item -ItemType Directory -Path $absoluteTempPath -Force | Out-Null
        }
        
        Write-Host "   Installing to temp directory: $absoluteTempPath" -ForegroundColor Gray
        
        # Verify we can find the module first
        Write-Host "   Verifying module availability..." -ForegroundColor Gray
        $moduleInfo = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction Stop
        if ($MinimumVersion -and $moduleInfo.Version -lt [version]$MinimumVersion) {
            throw "Module version $($moduleInfo.Version) is less than required $MinimumVersion"
        }
        
        Write-Host "   Installing to temp directory: $absoluteTempPath" -ForegroundColor Gray
        if ($DebugMode) {
            Write-Host "   DEBUG: HOME=$env:HOME, USERPROFILE=$env:USERPROFILE, TMP=$env:TMP" -ForegroundColor Gray
            Write-Host "   DEBUG: PSModulePath=$env:PSModulePath" -ForegroundColor Gray
            Write-Host "   DEBUG: Absolute temp path: $absoluteTempPath" -ForegroundColor Gray
        }
        
        # Use Save-Module with explicit absolute path
        # Ensure the path is a valid string and not empty
        if ([string]::IsNullOrWhiteSpace($absoluteTempPath)) {
            throw "Absolute temp path is null or empty: $absoluteTempPath"
        }
        
        # Verify path exists and is writable
        if (-not (Test-Path $absoluteTempPath)) {
            $null = New-Item -ItemType Directory -Path $absoluteTempPath -Force
        }
        
        # PowerShellGet's Save-Module internally uses paths that may resolve to empty strings
        # We need to ensure all environment variables are set before calling it
        # The path we pass should be fine, but internal dependency resolution might fail
        
        # PowerShellGet's Install-Module and Save-Module both fail due to internal path resolution
        # Workaround: Manually download and extract the module using NuGet API
        Write-Host "   Downloading module package directly..." -ForegroundColor Gray
        
        # Get module info to find download URL
        $moduleInfo = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction Stop
        $moduleVersion = if ($MinimumVersion -and $moduleInfo.Version -ge [version]$MinimumVersion) {
            $moduleInfo.Version
        } elseif ($MinimumVersion) {
            throw "Available version $($moduleInfo.Version) is less than required $MinimumVersion"
        } else {
            $moduleInfo.Version
        }
        
        # Construct NuGet package URL
        $packageName = $ModuleName.ToLower()
        $packageUrl = "https://www.powershellgallery.com/api/v2/package/$packageName/$moduleVersion"
        
        # Download to temp file
        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "$ModuleName-$moduleVersion.zip"
        try {
            Write-Host "   Downloading from: $packageUrl" -ForegroundColor Gray
            Invoke-WebRequest -Uri $packageUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
            
            # Extract to temp module path
            $moduleDestPath = Join-Path $absoluteTempPath $ModuleName
            if (Test-Path $moduleDestPath) {
                Remove-Item $moduleDestPath -Recurse -Force
            }
            New-Item -ItemType Directory -Path $moduleDestPath -Force | Out-Null
            
            # Extract ZIP file
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $moduleDestPath)
            
            Write-Host "   Module extracted to: $moduleDestPath" -ForegroundColor Gray
            
            # Find the module manifest (.psd1 file) in the extracted directory
            # NuGet packages extract with a versioned subdirectory
            $manifestPath = Get-ChildItem -Path $moduleDestPath -Filter "*.psd1" -Recurse | Select-Object -First 1
            if (-not $manifestPath) {
                throw "Module manifest (.psd1) not found in extracted package"
            }
            
            # Import using explicit path to avoid module name resolution issues
            $manifestDir = $manifestPath.DirectoryName
            Import-Module -Name $manifestDir -ErrorAction Stop
            Write-Host "   ✅ Successfully installed and imported $ModuleName" -ForegroundColor Green
        }
        finally {
            # Clean up temp ZIP
            if (Test-Path $tempZip) {
                Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Host "   ❌ Failed to install $ModuleName" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "   Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "   1. Check internet connectivity" -ForegroundColor Yellow
        Write-Host "   2. Verify PSGallery access: Find-Module $ModuleName" -ForegroundColor Yellow
        Write-Host "   3. Check temp directory: $tempModulePath" -ForegroundColor Yellow
        Write-Host "   4. Environment check - HOME: $env:HOME, USERPROFILE: $env:USERPROFILE" -ForegroundColor Yellow
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

# Explicitly import all required modules
Write-Host "📦 Importing required modules..." -ForegroundColor Cyan
foreach ($module in $requiredModules) {
    try {
        Import-Module $module.Name -Force -ErrorAction Stop
        Write-Host "   ✅ Imported $($module.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "   ❌ Failed to import $($module.Name): $_" -ForegroundColor Red
        exit 1
    }
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

