# V4 Migration Guide

**Version:** 4.0  
**Date:** 2026-02-12  

---

## Option A: Fresh V4 Deployment (Recommended)

If you have no existing V3 deployment or want a clean start:

```bash
# 1. Clone/download V4 scripts
cd tkt-azure-platform-v4/scripts

# 2. Make executable
chmod +x *.sh

# 3. Run deployment (dry-run first)
./deploy-avd-platform-v4.sh --dry-run

# 4. Run actual deployment
./deploy-avd-platform-v4.sh
```

**Time:** ~45 minutes  
**Result:** Complete AVD environment ready for users

---

## Option B: Migrate from V3

If you have a partial V3 deployment:

### Step 1: Check V3 State
```bash
# List existing resources
az resource list --resource-group rg-tktph-avd-sea --output table
```

### Step 2: Identify What Exists

| V3 Component | Check Command | If Missing |
|--------------|---------------|------------|
| VNet | `az network vnet list -g rg-tktph-avd-sea` | Run Phase 1 |
| Storage | `az storage account list -g rg-tktph-avd-sea` | Run Phase 2 |
| Host Pool | `az desktopvirtualization hostpool list -g rg-tktph-avd-sea` | Run Phase 3 |
| Session Hosts | `az vm list -g rg-tktph-avd-sea` | Run Phase 4 |
| Users | `az ad user list --filter "startswith(userPrincipalName,'ph-consultant')"` | Run Phase 5 |

### Step 3: Run Missing Phases

V4 scripts are idempotent - they skip existing resources:

```bash
# Run full deployment - it will skip what exists
./deploy-avd-platform-v4.sh

# Or run specific scripts
./setup-entra-id-automation.sh --domain yourdomain.onmicrosoft.com
./setup-fslogix-profiles.sh --resource-group rg-tktph-avd-sea --storage-account sttktphfslogix --vm-prefix tktph-sh --vm-count 2
```

### Step 4: Validate
```bash
./validate-deployment.sh --resource-group rg-tktph-avd-sea --host-pool tktph-hp
```

---

## Option C: Side-by-Side Deployment

Deploy V4 alongside V3 for testing:

```bash
# Use different resource group name
export RESOURCE_GROUP="rg-tktph-avd-v4-test"
./deploy-avd-platform-v4.sh
```

After validation, delete V3 resources and rename V4.

---

## Resource Group Naming

| Version | Resource Group | Status |
|---------|---------------|--------|
| V3 | rg-tktph-avd-sea | Existing/Partial |
| V4 | rg-tktph-avd | New default |

---

## Post-Deployment: Optional Features

After successful deployment, you can enable additional features:

### Enable VM Schedule (07:00-18:00 Brussels time)
```bash
./setup-vm-schedule.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2
```
**Savings:** ~€95/month (VMs only run during business hours)

### Enable Session Activity Logging
```bash
./setup-session-logging.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2
```
**Result:** All user activity logged to Log Analytics (free)

### Enable Video Session Recording (Teramind)
```bash
# Requires Teramind account (~€25/user/month)
./setup-session-logging.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2 \
    --enable-teramind \
    --teramind-key "YOUR_DEPLOYMENT_KEY"
```

---

## Rollback

If V4 deployment fails, resources can be deleted:

```bash
# WARNING: Destructive - removes all resources
az group delete --name rg-tktph-avd --yes --no-wait
```

Individual components can be removed selectively via Azure Portal.
