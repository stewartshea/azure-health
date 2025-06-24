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
```

### Check Specific Subscriptions

You can specify subscriptions using the `SUBSCRIPTIONS` environment variable in either format:

**Space-separated format:**
```bash
export SUBSCRIPTIONS="sub1-guid sub2-guid sub3-guid"
./role-assignment-quota-report.sh
```

**CSV format:**
```bash
export SUBSCRIPTIONS="sub1-guid,sub2-guid,sub3-guid"
./role-assignment-quota-report.sh
```

**One-liner examples:**
```bash
# Space-separated
SUBSCRIPTIONS="12345678-1234-1234-1234-123456789012 87654321-4321-4321-4321-210987654321" ./role-assignment-quota-report.sh

# CSV format
SUBSCRIPTIONS="12345678-1234-1234-1234-123456789012,87654321-4321-4321-4321-210987654321" ./role-assignment-quota-report.sh
