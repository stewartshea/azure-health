#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Test PowerShell environment for Azure scripts
.DESCRIPTION
    Validates that the PowerShell environment is properly configured
    to run Azure health monitoring scripts.
.EXAMPLE
    ./test-environment.ps1
#>

Write-Host "🔍 Azure PowerShell Environment Diagnostic" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$allChecks = @()

# Check 1: PowerShell Version
Write-Host "1️⃣  Checking PowerShell Version..." -ForegroundColor Cyan
$psVersion = $PSVersionTable.PSVersion
Write-Host "   Version: $psVersion" -ForegroundColor White
if ($psVersion.Major -ge 7 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -ge 1)) {
    Write-Host "   ✅ PowerShell version is supported" -ForegroundColor Green
    $allChecks += $true
} else {
    Write-Host "   ❌ PowerShell version is too old. Please upgrade to PowerShell 7+ or 5.1+" -ForegroundColor Red
    $allChecks += $false
}
Write-Host ""

# Check 2: PowerShell Edition
Write-Host "2️⃣  PowerShell Edition..." -ForegroundColor Cyan
$edition = $PSVersionTable.PSEdition
Write-Host "   Edition: $edition" -ForegroundColor White
Write-Host "   Platform: $($PSVersionTable.Platform ?? 'Windows')" -ForegroundColor Gray
Write-Host ""

# Check 3: NuGet Provider
Write-Host "3️⃣  Checking NuGet Package Provider..." -ForegroundColor Cyan
$nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
if ($nuget) {
    Write-Host "   Version: $($nuget.Version)" -ForegroundColor White
    Write-Host "   ✅ NuGet provider is installed" -ForegroundColor Green
    $allChecks += $true
} else {
    Write-Host "   ❌ NuGet provider is not installed" -ForegroundColor Red
    Write-Host "   Run: Install-PackageProvider -Name NuGet -Force" -ForegroundColor Yellow
    $allChecks += $false
}
Write-Host ""

# Check 4: PowerShell Gallery
Write-Host "4️⃣  Checking PowerShell Gallery..." -ForegroundColor Cyan
$psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($psGallery) {
    Write-Host "   Source: $($psGallery.SourceLocation)" -ForegroundColor White
    Write-Host "   Installation Policy: $($psGallery.InstallationPolicy)" -ForegroundColor White
    if ($psGallery.InstallationPolicy -eq 'Trusted') {
        Write-Host "   ✅ PSGallery is configured and trusted" -ForegroundColor Green
        $allChecks += $true
    } else {
        Write-Host "   ⚠️  PSGallery is not trusted (you'll be prompted during installs)" -ForegroundColor Yellow
        Write-Host "   Run: Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" -ForegroundColor Yellow
        $allChecks += $true
    }
} else {
    Write-Host "   ❌ PSGallery repository is not registered" -ForegroundColor Red
    Write-Host "   Run: Register-PSRepository -Default" -ForegroundColor Yellow
    $allChecks += $false
}
Write-Host ""

# Check 5: PowerShellGet
Write-Host "5️⃣  Checking PowerShellGet..." -ForegroundColor Cyan
$psGet = Get-Module -ListAvailable -Name PowerShellGet | Sort-Object Version -Descending | Select-Object -First 1
if ($psGet) {
    Write-Host "   Version: $($psGet.Version)" -ForegroundColor White
    if ($psGet.Version -ge [version]"2.0.0") {
        Write-Host "   ✅ PowerShellGet is up to date" -ForegroundColor Green
        $allChecks += $true
    } else {
        Write-Host "   ⚠️  PowerShellGet is outdated (consider updating)" -ForegroundColor Yellow
        Write-Host "   Run: Install-Module PowerShellGet -Force -AllowClobber" -ForegroundColor Yellow
        $allChecks += $true
    }
} else {
    Write-Host "   ❌ PowerShellGet is not installed" -ForegroundColor Red
    $allChecks += $false
}
Write-Host ""

# Check 6: Internet Connectivity to PSGallery
Write-Host "6️⃣  Checking Internet Connectivity to PSGallery..." -ForegroundColor Cyan
try {
    $test = Find-Module -Name Az.Accounts -ErrorAction Stop | Select-Object -First 1
    Write-Host "   Latest Az.Accounts: $($test.Version)" -ForegroundColor White
    Write-Host "   ✅ Can reach PowerShell Gallery" -ForegroundColor Green
    $allChecks += $true
} catch {
    Write-Host "   ❌ Cannot reach PowerShell Gallery: $_" -ForegroundColor Red
    Write-Host "   Check your internet connection or proxy settings" -ForegroundColor Yellow
    $allChecks += $false
}
Write-Host ""

# Check 7: Azure Modules
Write-Host "7️⃣  Checking Azure PowerShell Modules..." -ForegroundColor Cyan
$azModules = @("Az.Accounts", "Az.Resources", "Az.ResourceGraph")
$moduleResults = @{}

foreach ($moduleName in $azModules) {
    $module = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
    if ($module) {
        Write-Host "   ✅ $moduleName : $($module.Version)" -ForegroundColor Green
        $moduleResults[$moduleName] = $true
    } else {
        Write-Host "   ❌ $moduleName : Not installed" -ForegroundColor Red
        $moduleResults[$moduleName] = $false
    }
}

if ($moduleResults.Values -contains $false) {
    Write-Host ""
    Write-Host "   Run the main script to auto-install missing modules" -ForegroundColor Yellow
    $allChecks += $false
} else {
    $allChecks += $true
}
Write-Host ""

# Check 8: Azure Authentication
Write-Host "8️⃣  Checking Azure Authentication..." -ForegroundColor Cyan
try {
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -ne $context) {
        Write-Host "   Account: $($context.Account.Id)" -ForegroundColor White
        Write-Host "   Tenant: $($context.Tenant.Id)" -ForegroundColor White
        Write-Host "   Subscription: $($context.Subscription.Name)" -ForegroundColor White
        Write-Host "   ✅ Authenticated to Azure" -ForegroundColor Green
        $allChecks += $true
    } else {
        Write-Host "   ⚠️  Not authenticated to Azure" -ForegroundColor Yellow
        Write-Host "   Run: Connect-AzAccount" -ForegroundColor Yellow
        $allChecks += $true
    }
} catch {
    Write-Host "   ⚠️  Cannot check authentication (Az.Accounts not available)" -ForegroundColor Yellow
    Write-Host "   Install Azure modules first" -ForegroundColor Yellow
    $allChecks += $true
}
Write-Host ""

# Summary
Write-Host "==========================================" -ForegroundColor Cyan
$failedChecks = ($allChecks | Where-Object { $_ -eq $false }).Count
$totalChecks = $allChecks.Count

if ($failedChecks -eq 0) {
    Write-Host "✅ All checks passed! Environment is ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run: ./subscriptions/role-assignment-quota-report.ps1" -ForegroundColor Cyan
} else {
    Write-Host "⚠️  $failedChecks out of $totalChecks checks failed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please address the issues above before running Azure scripts." -ForegroundColor Yellow
    Write-Host "The main script will attempt to fix most issues automatically." -ForegroundColor Cyan
}
Write-Host ""

