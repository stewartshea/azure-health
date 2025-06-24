# Azure Role Assignment Quota Report

This script checks the number of role assignments used in one or more Azure subscriptions and compares it against the dynamically fetched quota limit for each subscription. It helps identify subscriptions that are near or at the quota limit.

The script automatically retrieves the actual quota limit for each subscription using Azure's Role Assignment Usage Metrics API, which can vary between subscriptions (commonly 2000 or 4000 assignments per subscription).

## 🔧 Requirements

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- Access to run `az rest` and list role assignments for the target subscriptions
- Sufficient permissions to query role assignment usage metrics

## 📦 Usage

### Basic Usage (check all accessible subscriptions)

```bash
./role-assignment-quota-report.sh
