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

# Set ALL environment variables FIRST, before any operations
# Use CODEBUNDLE_TEMP_DIR if available, otherwise use temp path
$basePath = if (-not [string]::IsNullOrEmpty($env:CODEBUNDLE_TEMP_DIR)) {
    $env:CODEBUNDLE_TEMP_DIR
} else {
    [System.IO.Path]::GetTempPath()
}

# Set HOME FIRST (required for module path resolution on Linux/Mac)
# Az.Accounts startup script uses $HOME (PowerShell variable), not $env:HOME
if ([string]::IsNullOrEmpty($env:HOME)) {
    $env:HOME = $basePath
}
# Also set PowerShell $HOME variable (Az.Accounts uses this in its startup script)
# $HOME is read-only, so we need to use Set-Variable with -Force
# Ensure we use the actual path value, not a variable reference
$homeValue = if (-not [string]::IsNullOrEmpty($env:CODEBUNDLE_TEMP_DIR)) {
    $env:CODEBUNDLE_TEMP_DIR
} else {
    $basePath
}
if ([string]::IsNullOrEmpty($HOME) -or $HOME -eq '$CODEBUNDLE_TEMP_DIR') {
    Set-Variable -Name HOME -Value $homeValue -Force -Option AllScope
}

# Set USERPROFILE (Windows equivalent, PowerShell may check this)
if ([string]::IsNullOrEmpty($env:USERPROFILE)) {
    $env:USERPROFILE = $basePath
}

# Set TMP/TEMP (used for temporary files during module operations)
if ([string]::IsNullOrEmpty($env:TMP)) {
    $env:TMP = $basePath
}
if ([string]::IsNullOrEmpty($env:TEMP)) {
    $env:TEMP = $basePath
}

# Set USER/USERNAME (some module operations may check this)
if ([string]::IsNullOrEmpty($env:USER) -and [string]::IsNullOrEmpty($env:USERNAME)) {
    $env:USER = "pwsh-user"
    $env:USERNAME = "pwsh-user"
}

# Set PATH (required for many operations)
if ([string]::IsNullOrEmpty($env:PATH)) {
    $env:PATH = "/usr/local/bin:/usr/bin:/bin"
}
else {
    # Ensure temp path is in PATH
    if ($env:PATH -notlike "*${basePath}*") {
        $env:PATH = "${basePath}:$env:PATH"
    }
}

# Also set environment variables via .NET so modules can access them during initialization
# This ensures .NET Environment methods can resolve paths correctly
[Environment]::SetEnvironmentVariable('HOME', $env:HOME, 'Process')
[Environment]::SetEnvironmentVariable('USERPROFILE', $env:USERPROFILE, 'Process')
[Environment]::SetEnvironmentVariable('TMP', $env:TMP, 'Process')
[Environment]::SetEnvironmentVariable('TEMP', $env:TEMP, 'Process')
[Environment]::SetEnvironmentVariable('PATH', $env:PATH, 'Process')

# Output all environment variables for debugging
Write-Host "🔧 Environment Variables:" -ForegroundColor Cyan
Write-Host "   HOME: $env:HOME" -ForegroundColor Gray
Write-Host "   USERPROFILE: $env:USERPROFILE" -ForegroundColor Gray
Write-Host "   TMP: $env:TMP" -ForegroundColor Gray
Write-Host "   TEMP: $env:TEMP" -ForegroundColor Gray
Write-Host "   USER: $env:USER" -ForegroundColor Gray
Write-Host "   USERNAME: $env:USERNAME" -ForegroundColor Gray
Write-Host "   PATH: $env:PATH" -ForegroundColor Gray
Write-Host "   CODEBUNDLE_TEMP_DIR: $env:CODEBUNDLE_TEMP_DIR" -ForegroundColor Gray
Write-Host "   basePath: $basePath" -ForegroundColor Gray
Write-Host ""

# Create temporary module directory
$tempModulePath = Join-Path ([System.IO.Path]::GetTempPath()) "AzurePSModules_$PID"
New-Item -ItemType Directory -Path $tempModulePath -Force | Out-Null

# Add temp path to PSModulePath for this session
$env:PSModulePath = "$tempModulePath$([IO.Path]::PathSeparator)$env:PSModulePath"

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
    if ($env:PATH -notlike "*${basePath}*") {
        $env:PATH = "${basePath}:$env:PATH"
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
    
    # Check if module is in our temp path (reliable location)
    $moduleInTempPath = Join-Path $tempModulePath $ModuleName
    if (Test-Path $moduleInTempPath) {
        Write-Host "   ✅ Module $ModuleName is already installed in temp path" -ForegroundColor Green
        return
    }
    
    # Check if module is installed elsewhere
    if (Test-ModuleInstalled -ModuleName $ModuleName) {
        Write-Host "   ⚠️  Module $ModuleName is installed but may have path issues" -ForegroundColor Yellow
        Write-Host "   Reinstalling to temp directory to avoid path resolution problems..." -ForegroundColor Yellow
        # Fall through to installation logic below
    }
    else {
        Write-Host "   ⚠️  Module $ModuleName not found. Installing..." -ForegroundColor Yellow
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
            
            # Verify module was extracted correctly
            $manifestPath = Get-ChildItem -Path $moduleDestPath -Filter "*.psd1" -Recurse | Select-Object -First 1
            if (-not $manifestPath) {
                throw "Module manifest (.psd1) not found in extracted package"
            }
            
            # Module is now in PSModulePath, so it will be discoverable
            # Don't import here - let the later import step handle it to avoid path resolution issues
            Write-Host "   ✅ Successfully installed $ModuleName" -ForegroundColor Green
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
        # Try to find module in our temp path first
        $modulePath = Join-Path $tempModulePath $module.Name
        if (Test-Path $modulePath) {
            # Find manifest in the module directory
            $manifest = Get-ChildItem -Path $modulePath -Filter "*.psd1" -Recurse | Select-Object -First 1
            if ($manifest) {
                # Get absolute paths
                $manifestFullPath = [System.IO.Path]::GetFullPath($manifest.FullName)
                $manifestDir = [System.IO.Path]::GetFullPath($manifest.DirectoryName)
                
                if ([string]::IsNullOrWhiteSpace($manifestFullPath) -or [string]::IsNullOrWhiteSpace($manifestDir)) {
                    throw "Manifest path is empty - FullPath: $manifestFullPath, Directory: $manifestDir"
                }
                
                if ($DebugMode) {
                    Write-Host "   DEBUG: Manifest file: $manifestFullPath" -ForegroundColor Gray
                    Write-Host "   DEBUG: Manifest directory: $manifestDir" -ForegroundColor Gray
                }
                
                # Import using the module name - it should find it via PSModulePath now
                # The temp path is already in PSModulePath, so PowerShell should discover it
                # This avoids passing paths directly to Import-Module which triggers path resolution
                try {
                    # Temporarily set PSModulePath to only our temp path to force discovery there
                    $originalPSModulePath = $env:PSModulePath
                    $env:PSModulePath = "$tempModulePath$([IO.Path]::PathSeparator)$originalPSModulePath"
                    
                    # Now import by name - it should find the module in our temp path
                    Import-Module -Name $module.Name -Force -ErrorAction Stop
                    
                    # Restore original PSModulePath
                    $env:PSModulePath = $originalPSModulePath
                    
                    Write-Host "   ✅ Imported $($module.Name)" -ForegroundColor Green
                }
                catch {
                    # Restore PSModulePath on error
                    $env:PSModulePath = $originalPSModulePath
                    
                    # If that fails, the module might have initialization code that's failing
                    # Try to get more details about what's failing
                    if ($DebugMode) {
                        Write-Host "   DEBUG: Import by name failed: $_" -ForegroundColor Gray
                        Write-Host "   DEBUG: PSModulePath was: $env:PSModulePath" -ForegroundColor Gray
                        Write-Host "   DEBUG: Module path: $modulePath" -ForegroundColor Gray
                        Write-Host "   DEBUG: Manifest: $manifestFullPath" -ForegroundColor Gray
                    }
                    throw "Failed to import $($module.Name): $_"
                }
            }
            else {
                throw "Manifest not found in $modulePath"
            }
        }
        else {
            # Module not in temp path, try normal import
            Import-Module $module.Name -Force -ErrorAction Stop
            Write-Host "   ✅ Imported $($module.Name)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "   ❌ Failed to import $($module.Name): $_" -ForegroundColor Red
        if (Test-Path $modulePath) {
            Write-Host "   Module path exists: $modulePath" -ForegroundColor Gray
            $manifest = Get-ChildItem -Path $modulePath -Filter "*.psd1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($manifest) {
                Write-Host "   Manifest found: $($manifest.FullName)" -ForegroundColor Gray
                Write-Host "   Manifest directory: $($manifest.DirectoryName)" -ForegroundColor Gray
                $absPath = [System.IO.Path]::GetFullPath($manifest.DirectoryName)
                Write-Host "   Absolute path: $absPath" -ForegroundColor Gray
            }
        }
        exit 1
    }
}
Write-Host ""

#endregion

#region Azure Authentication

Write-Host "🔐 Checking Azure authentication status..." -ForegroundColor Cyan

# Check if AZURE_CONFIG_DIR is set (from az login)
if (-not [string]::IsNullOrEmpty($env:AZURE_CONFIG_DIR)) {
    Write-Host "   Using Azure config directory: $env:AZURE_CONFIG_DIR" -ForegroundColor Gray
    # Az.Accounts should automatically use AZURE_CONFIG_DIR if set
    # But we can also explicitly set it for the module
    $env:AZURE_CONFIG_DIR = $env:AZURE_CONFIG_DIR
}

try {
    # Try to import context from Azure CLI if available
    # Az.Accounts can use credentials from az login if AZURE_CONFIG_DIR is set
    $context = Get-AzContext -ErrorAction SilentlyContinue
    
    # If no context but AZURE_CONFIG_DIR exists, try to import from Azure CLI
    if ($null -eq $context -and -not [string]::IsNullOrEmpty($env:AZURE_CONFIG_DIR)) {
        Write-Host "   Attempting to import context from Azure CLI..." -ForegroundColor Gray
        try {
            # Check for Azure CLI profile file
            $azProfilePath = Join-Path $env:AZURE_CONFIG_DIR "azureProfile.json"
            $azAccessTokensPath = Join-Path $env:AZURE_CONFIG_DIR "accessTokens.json"
            
            if (Test-Path $azProfilePath) {
                Write-Host "   Found Azure CLI profile at: $azProfilePath" -ForegroundColor Gray
                
                # Try to import context using Import-AzContext
                # First, enable context autosave to the same directory
                try {
                    Enable-AzContextAutosave -Scope Process -ErrorAction SilentlyContinue
                }
                catch {
                    # Ignore if already enabled
                }
                
                # Az.Accounts doesn't automatically import Azure CLI credentials
                # We need to bridge them by using az account get-access-token
                Write-Host "   Bridging Azure CLI credentials to Az.Accounts..." -ForegroundColor Gray
                
                # First verify Azure CLI is authenticated
                $azAccount = az account show --output json 2>$null | ConvertFrom-Json
                if ($azAccount -and $azAccount.id) {
                    Write-Host "   Azure CLI authenticated as: $($azAccount.user.name)" -ForegroundColor Gray
                    Write-Host "   Subscription: $($azAccount.name) ($($azAccount.id))" -ForegroundColor Gray
                    
                    # Get access token from Azure CLI
                    Write-Host "   Getting access token from Azure CLI..." -ForegroundColor Gray
                    $tokenResponse = az account get-access-token --output json 2>$null | ConvertFrom-Json
                    
                    if ($tokenResponse -and $tokenResponse.accessToken) {
                        # Use the token to authenticate with Az.Accounts
                        # Connect-AzAccount can use an access token
                        Write-Host "   Using access token to authenticate Az.Accounts..." -ForegroundColor Gray
                        
                        # Create a secure string from the token
                        $secureToken = ConvertTo-SecureString $tokenResponse.accessToken -AsPlainText -Force
                        
                        # Connect using the token
                        # Note: Connect-AzAccount with -AccessToken requires the account and tenant
                        $accountId = $azAccount.user.name
                        $tenantId = $azAccount.tenantId
                        $subscriptionId = $azAccount.id
                        
                        # Az.Accounts doesn't directly accept Azure CLI access tokens
                        # We need to use a different approach - try to use the token with Invoke-AzRestMethod
                        # or use Connect-AzAccount with device code (won't work in non-interactive)
                        # For now, we'll note that Azure CLI is working and suggest manual connection
                        Write-Host "   Azure CLI is authenticated, but Az.Accounts requires separate authentication" -ForegroundColor Yellow
                        Write-Host "   Az.Accounts and Azure CLI use different credential stores" -ForegroundColor Yellow
                        Write-Host "   To use Az.Accounts, run: Connect-AzAccount -UseDeviceAuthentication" -ForegroundColor Yellow
                        Write-Host "   Or use service principal: Connect-AzAccount -ServicePrincipal -Credential `$cred -TenantId `$tenantId" -ForegroundColor Yellow
                        
                        # However, we can try to use the token for REST API calls if needed
                        # For now, we'll continue and see if any contexts are available
                    }
                    else {
                        Write-Host "   Could not get access token from Azure CLI" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host "   Azure CLI is not authenticated" -ForegroundColor Yellow
                }
                
                # Fallback: try listing available contexts
                if ($null -eq $context) {
                    $availableContexts = Get-AzContext -ListAvailable -ErrorAction SilentlyContinue
                    if ($availableContexts) {
                        Write-Host "   Found $($availableContexts.Count) available context(s), selecting first..." -ForegroundColor Gray
                        $context = $availableContexts | Select-Object -First 1
                        Set-AzContext -Context $context -ErrorAction Stop | Out-Null
                        $context = Get-AzContext -ErrorAction Stop
                    }
                }
            }
            else {
                Write-Host "   Azure CLI profile not found at: $azProfilePath" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "   Could not import from Azure CLI: $_" -ForegroundColor Yellow
        }
    }
    
    # Validate context is actually authenticated (has Account and Tenant)
    $isValidContext = $null -ne $context -and 
                      -not [string]::IsNullOrEmpty($context.Account) -and 
                      -not [string]::IsNullOrEmpty($context.Account.Id) -and
                      -not [string]::IsNullOrEmpty($context.Tenant) -and
                      -not [string]::IsNullOrEmpty($context.Tenant.Id)
    
    if (-not $isValidContext) {
        Write-Host "⚠️  Not authenticated to Azure or context is invalid." -ForegroundColor Yellow
        
        # Check if we're in a non-interactive environment
        if (-not [Environment]::UserInteractive -or $null -ne [Console]::In -and [Console]::In.Peek() -eq -1) {
            Write-Host "   Non-interactive session detected. Use one of the following:" -ForegroundColor Yellow
            Write-Host "   - Connect-AzAccount -UseDeviceAuthentication" -ForegroundColor Yellow
            Write-Host "   - Connect-AzAccount -ServicePrincipal -Credential `$cred -TenantId `$tenantId" -ForegroundColor Yellow
            Write-Host "   - Connect-AzAccount -Identity (for managed identity)" -ForegroundColor Yellow
            Write-Host "   - Set environment variables: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID" -ForegroundColor Yellow
            if (-not [string]::IsNullOrEmpty($env:AZURE_CONFIG_DIR)) {
                Write-Host "   - Or ensure 'az login' credentials are valid in: $env:AZURE_CONFIG_DIR" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "   Attempting interactive authentication..." -ForegroundColor Yellow
            Connect-AzAccount -ErrorAction Stop
            $context = Get-AzContext -ErrorAction Stop
        }
        
        # Re-validate after authentication attempt
        $isValidContext = $null -ne $context -and 
                          -not [string]::IsNullOrEmpty($context.Account) -and 
                          -not [string]::IsNullOrEmpty($context.Account.Id) -and
                          -not [string]::IsNullOrEmpty($context.Tenant) -and
                          -not [string]::IsNullOrEmpty($context.Tenant.Id)
        
        if (-not $isValidContext) {
            throw "Authentication failed or context is invalid. Please authenticate to Azure first."
        }
    }
    
    Write-Host "✅ Authenticated as: $($context.Account.Id)" -ForegroundColor Green
    Write-Host "   Tenant: $($context.Tenant.Id)" -ForegroundColor Gray
    if ($context.Subscription) {
        Write-Host "   Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Gray
    }
    Write-Host ""
}
catch {
    Write-Host "❌ Failed to authenticate to Azure: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please authenticate using one of these methods:" -ForegroundColor Yellow
    Write-Host "  Connect-AzAccount -UseDeviceAuthentication" -ForegroundColor Yellow
    Write-Host "  Connect-AzAccount -ServicePrincipal -Credential `$cred -TenantId `$tenantId" -ForegroundColor Yellow
    Write-Host "  Connect-AzAccount -Identity" -ForegroundColor Yellow
    if (-not [string]::IsNullOrEmpty($env:AZURE_CONFIG_DIR)) {
        Write-Host "  Or ensure 'az login' credentials are valid in: $env:AZURE_CONFIG_DIR" -ForegroundColor Yellow
    }
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

