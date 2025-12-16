# Azure Health Monitoring Scripts

A collection of small and quick Azure scripts for monitoring and reporting on Azure resource health, quotas, and usage.

## Available Scripts

### Bash Scripts (`subscriptions/`)
- **role-assignment-quota-report.sh** - Monitor role assignment quotas across Azure subscriptions (Azure CLI)

### PowerShell Scripts (`powershell/`)
- **role-assignment-quota-report.ps1** - Monitor role assignment quotas across Azure subscriptions (Azure PowerShell)
- **test-environment.ps1** - Validate PowerShell environment setup and prerequisites

## Quick Start

### Bash (Azure CLI)
```bash
cd subscriptions
./role-assignment-quota-report.sh
```

### PowerShell
```powershell
# Optional: Test your environment first
./powershell/test-environment.ps1

# Run the quota report
./powershell/subscriptions/role-assignment-quota-report.ps1
```

## Documentation

- [PowerShell Scripts Documentation](./powershell/README.md)
- [Bash Scripts Documentation](./subscriptions/README.md)

## Requirements

### Bash Scripts
- Azure CLI installed and authenticated
- Bash 4.0 or higher
- `jq` (for JSON processing)

### PowerShell Scripts
- PowerShell 7.0+ or PowerShell 5.1+
- Internet connectivity (for module installation)
- Azure PowerShell modules (auto-installed by script)