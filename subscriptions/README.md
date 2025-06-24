# Azure Role Assignment Quota Report

This script checks the number of role assignments used in one or more Azure subscriptions and compares it against the default quota (2000 assignments per subscription). It helps identify subscriptions that are near or at the quota limit.

## 🔧 Requirements

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- Access to run `az rest` and list role assignments for the target subscriptions

## 📦 Usage

### Basic Usage (check all accessible subscriptions)

```bash
./role-assignment-quota-report.sh
