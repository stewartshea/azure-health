# PowerShell Scripts for Azure Health Monitoring

This directory contains PowerShell scripts for monitoring and reporting on Azure resource health and quotas.

## Prerequisites

### PowerShell Version
- **PowerShell Core (pwsh) 7.0+** is recommended
- Windows PowerShell 5.1 is also supported but may require additional setup

To check your PowerShell version:
```powershell
$PSVersionTable
```

### Required Setup

The scripts will automatically check and install required components, but you may need to perform some initial setup:

#### 1. Install PowerShell Core (if not already installed)

**Linux (Ubuntu/Debian):**
```bash
# Install via snap
sudo snap install powershell --classic

# Or via apt
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
```

**macOS:**
```bash
brew install --cask powershell
```

**Windows:**
Download from: https://github.com/PowerShell/PowerShell/releases

#### 2. Ensure NuGet Provider is Available

If you encounter module installation errors, manually install NuGet:

```powershell
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
```

#### 3. Configure PowerShell Gallery

Set PSGallery as a trusted repository:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
```

## Scripts

### role-assignment-quota-report.ps1

Monitors Azure role assignment quotas across subscriptions and alerts on high usage.

**Features:**
- Automatic module installation and environment setup
- Checks NuGet provider, PowerShell Gallery, and PowerShellGet
- Installs required Azure modules (Az.Accounts, Az.Resources, Az.ResourceGraph)
- Retrieves dynamic quota limits from Azure API
- Reports usage with clear visual indicators
- Supports filtering specific subscriptions

**Usage:**

```powershell
# Check all subscriptions
./role-assignment-quota-report.ps1

# Check specific subscriptions
./role-assignment-quota-report.ps1 -Subscriptions "sub-id-1,sub-id-2"

# Enable debug mode
./role-assignment-quota-report.ps1 -DebugMode

# Using environment variables
$env:SUBSCRIPTIONS="sub-id-1,sub-id-2"
./role-assignment-quota-report.ps1
```

**Output Indicators:**
- ✅ Green - Within safe quota range (< 90%)
- ⚠️ Yellow - Usage above 90% or warnings
- ❌ Red - Quota exceeded or errors

## Troubleshooting

### "Cannot bind argument to parameter 'Path' because it is an empty string"

This error typically indicates missing prerequisites. The script now automatically handles this by:
1. Installing NuGet package provider
2. Configuring PSGallery as trusted
3. Checking/updating PowerShellGet

If issues persist, manually run:
```powershell
Install-PackageProvider -Name NuGet -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module PowerShellGet -Force -AllowClobber
```

Then restart PowerShell and try again.

### "Module not found after installation"

Try importing the module manually:
```powershell
Import-Module Az.Accounts
Import-Module Az.Resources
Import-Module Az.ResourceGraph
```

If this fails, check module installation location:
```powershell
$env:PSModulePath -split [IO.Path]::PathSeparator
Get-Module -ListAvailable
```

### "Execution policy" errors (Windows only)

Set execution policy to allow script execution:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Internet connectivity issues

If behind a proxy, configure PowerShell to use it:
```powershell
# Set proxy for current session
$proxy = [System.Net.WebProxy]::new('http://proxy.example.com:8080')
[System.Net.WebRequest]::DefaultWebProxy = $proxy

# Or set system-wide
[System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
```

### "Insufficient permissions" errors

For Azure operations, ensure you have:
- Reader access on subscriptions you want to monitor
- Permissions to query Azure Resource Graph
- Valid Azure authentication (the script will prompt if needed)

### Manual module installation

If automatic installation fails, install modules manually:

```powershell
# Install required modules
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Az.Resources -Scope CurrentUser -Force  
Install-Module -Name Az.ResourceGraph -Scope CurrentUser -Force

# Verify installation
Get-Module -ListAvailable -Name Az.*
```

## Authentication

The scripts use Azure PowerShell authentication. If not already logged in, you'll be prompted to authenticate:

```powershell
# Login interactively
Connect-AzAccount

# Login with service principal
Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId

# Login with managed identity
Connect-AzAccount -Identity
```

## Support

For issues with:
- **Scripts**: Open an issue in this repository
- **PowerShell**: https://github.com/PowerShell/PowerShell/issues
- **Azure PowerShell modules**: https://github.com/Azure/azure-powershell/issues

