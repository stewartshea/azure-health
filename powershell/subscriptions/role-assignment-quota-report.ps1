#!/usr/local/bin/pwsh

# Super simple script: install Azure module and list subscriptions
# Assumes az login has been run in bash session before this is called

# Install Az.Accounts module if not present
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Install-Module -Name Az.Accounts -Scope CurrentUser -Force
}

# Import the module
Import-Module Az.Accounts

# List subscriptions
Get-AzSubscription

