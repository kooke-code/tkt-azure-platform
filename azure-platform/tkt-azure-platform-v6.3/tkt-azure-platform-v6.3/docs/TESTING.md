# V4 Testing Guide

**Version:** 4.0  
**Date:** 2026-02-12  

---

## Prerequisites

- Azure CLI v2.50+ installed
- Contributor role on Azure subscription
- Global Administrator role in Entra ID
- Graph API permissions (User.ReadWrite.All, Group.ReadWrite.All)

---

## Quick Test (Dry-Run)

Test deployment logic without creating resources:

```bash
cd tkt-azure-platform-v4/scripts
chmod +x *.sh

# Dry-run shows what would be deployed
./deploy-avd-platform-v4.sh --dry-run
```

**Expected output:** Resource names, configuration details, no actual API calls.

---

## Development Testing

### 1. Create Test Resource Group

```bash
export RESOURCE_GROUP="rg-tktph-avd-dev"
export LOCATION="southeastasia"

az group create --name $RESOURCE_GROUP --location $LOCATION --tags Environment=Development
```

### 2. Run Individual Scripts

Test each script independently:

```bash
# Test networking only
az network vnet create --resource-group $RESOURCE_GROUP --name test-vnet --address-prefix 10.99.0.0/16

# Test storage only  
az storage account create --resource-group $RESOURCE_GROUP --name sttkttest$RANDOM --sku Premium_LRS --kind FileStorage

# Test identity script (creates test users)
./setup-entra-id-automation.sh --resource-group $RESOURCE_GROUP --domain yourdomain.onmicrosoft.com --dry-run
```

### 3. Validate Script Syntax

```bash
# Check bash syntax
for script in *.sh; do
    bash -n "$script" && echo "✓ $script OK" || echo "✗ $script FAILED"
done
```

---

## Integration Testing

### Full Deployment Test

```bash
# Create isolated test environment
./deploy-avd-platform-v4.sh \
    --resource-group rg-tktph-avd-test \
    --dry-run

# If dry-run looks good, deploy
./deploy-avd-platform-v4.sh --resource-group rg-tktph-avd-test
```

### Validation Suite

```bash
# Run all validation tests
./validate-deployment.sh \
    --resource-group rg-tktph-avd-test \
    --host-pool tktph-hp \
    --output json \
    --output-file test-results.json
```

**Expected:** All tests PASS or WARN (no FAIL)

---

## Test Scenarios

### Scenario 1: Network Connectivity

```bash
# From session host, test AVD gateway
Test-NetConnection -ComputerName rdweb.wvd.microsoft.com -Port 443
Test-NetConnection -ComputerName rdbroker.wvd.microsoft.com -Port 443
```

### Scenario 2: Storage Connectivity

```bash
# From session host, test Azure Files
Test-NetConnection -ComputerName sttktphfslogix.file.core.windows.net -Port 445
```

### Scenario 3: User Login

1. Open https://rdweb.wvd.microsoft.com/arm/webclient
2. Sign in as ph-consultant-001@yourdomain.onmicrosoft.com
3. Launch "Session Desktop"
4. Verify profile creates in Azure Files

### Scenario 4: FSLogix Profile

```bash
# On session host, check profile folder
dir \\sttktphfslogix.file.core.windows.net\profiles

# Check FSLogix status
& "C:\Program Files\FSLogix\Apps\frx.exe" list-redirects
```

---

## Cleanup Test Environment

```bash
# Delete test resource group
az group delete --name rg-tktph-avd-test --yes --no-wait

# Delete test users
az ad user delete --id ph-consultant-001@yourdomain.onmicrosoft.com
az ad user delete --id ph-consultant-002@yourdomain.onmicrosoft.com
# ... etc
```

---

## CI/CD Integration (Future)

```yaml
# Example GitHub Actions workflow
name: AVD Deployment Test

on:
  pull_request:
    paths:
      - 'scripts/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Syntax Check
        run: |
          for script in scripts/*.sh; do
            bash -n "$script"
          done
      
      - name: Dry Run
        run: |
          ./scripts/deploy-avd-platform-v4.sh --dry-run
```

---

## Testing Optional Features

### Test VM Schedule (07:00-18:00 Brussels)

```bash
# Dry-run first
./setup-vm-schedule.sh \
    --resource-group rg-tktph-avd-test \
    --vm-prefix tktph-sh \
    --vm-count 2 \
    --dry-run

# Verify automation account exists after deployment
az automation account list --resource-group rg-tktph-avd-test --output table

# Check schedules
az automation schedule list \
    --resource-group rg-tktph-avd-test \
    --automation-account-name aa-tktph-vmschedule \
    --output table
```

### Test Session Logging

```bash
# Dry-run first
./setup-session-logging.sh \
    --resource-group rg-tktph-avd-test \
    --vm-prefix tktph-sh \
    --vm-count 2 \
    --dry-run

# After deployment, verify DCR exists
az monitor data-collection rule list \
    --resource-group rg-tktph-avd-test \
    --output table

# Test logs appear in Log Analytics (wait ~15 min after deployment)
az monitor log-analytics query \
    --workspace rg-tktph-avd-test \
    --analytics-query "SecurityEvent | where TimeGenerated > ago(1h) | limit 10"
```

---

## Troubleshooting Tests

| Issue | Check | Fix |
|-------|-------|-----|
| Script not executable | `ls -la *.sh` | `chmod +x *.sh` |
| Azure CLI not logged in | `az account show` | `az login` |
| Wrong subscription | `az account show` | `az account set -s <id>` |
| Graph API permissions | Check Entra ID app registrations | Grant admin consent |
