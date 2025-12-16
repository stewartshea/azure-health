#!/usr/local/bin/pwsh

# Super simple script: install Azure module and list subscriptions
# Assumes az login has been run in bash session before this is called

# Install Az.Accounts module if not present
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Install-Module -Name Az.Accounts -Scope CurrentUser -Force
}

# Import the module
Import-Module Az.Accounts

# Bridge Azure CLI credentials to Az.Accounts
# If AZURE_CONFIG_DIR is set, enable context autosave to that directory
if (-not [string]::IsNullOrEmpty($env:AZURE_CONFIG_DIR)) {
    Enable-AzContextAutosave -Scope Process -ErrorAction SilentlyContinue
    # Try to import context from Azure CLI profile
    $azProfilePath = Join-Path $env:AZURE_CONFIG_DIR "AzureRmContext.json"
    if (Test-Path $azProfilePath) {
        Import-AzContext -Path $azProfilePath -ErrorAction SilentlyContinue
    }
}

# If still not authenticated, try to connect using Azure CLI token
$context = Get-AzContext -ErrorAction SilentlyContinue
if ($null -eq $context) {
    # Get token from Azure CLI and connect
    $tokenResponse = az account get-access-token --output json 2>$null | ConvertFrom-Json
    if ($tokenResponse -and $tokenResponse.accessToken) {
        $azAccount = az account show --output json 2>$null | ConvertFrom-Json
        if ($azAccount) {
            # Connect using the token (requires tenant and subscription)
            $tenantId = $azAccount.tenantId
            $subscriptionId = $azAccount.id
            Connect-AzAccount -AccessToken $tokenResponse.accessToken -AccountId $azAccount.user.name -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction SilentlyContinue
        }
    }
}

# List subscriptions
Get-AzSubscription

