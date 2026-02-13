# Migration Guide - V4/V5 to V6.2

**Version:** 6.2  
**Date:** February 13, 2026

---

## Overview

V6.2 fixes critical Entra ID join issues that caused session hosts to show "Unavailable" status. This guide covers migrating existing V4/V5 deployments to V6.2.

---

## What Changed in V6.2

| Component | V4/V5 | V6.2 |
|-----------|-------|------|
| VM Identity | None | System-assigned managed identity |
| Join Type | Not configured | Entra ID join (AADLoginForWindows) |
| DSC aadJoin | Not set | `"aadJoin": true` |
| VM RBAC | Not assigned | Virtual Machine User Login role |
| Wait Time | 30 seconds | 90 seconds (for Entra join) |

---

## Migration Options

### Option A: Fix Existing VMs (Recommended)

Keep your current deployment and add Entra ID join configuration.

**Time:** ~10 minutes  
**Downtime:** VMs restart (2-3 minutes per VM)

```bash
# Run the fix script
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea
```

**Or run manually:**

```bash
# 1. Enable managed identity
az vm identity assign -g rg-tktph-avd-prod-sea -n vm-tktph-01
az vm identity assign -g rg-tktph-avd-prod-sea -n vm-tktph-02

# 2. Install AADLoginForWindows extension
az vm extension set \
    --resource-group rg-tktph-avd-prod-sea \
    --vm-name vm-tktph-01 \
    --name "AADLoginForWindows" \
    --publisher "Microsoft.Azure.ActiveDirectory" \
    --version "2.0"

az vm extension set \
    --resource-group rg-tktph-avd-prod-sea \
    --vm-name vm-tktph-02 \
    --name "AADLoginForWindows" \
    --publisher "Microsoft.Azure.ActiveDirectory" \
    --version "2.0"

# 3. Assign VM login role
GROUP_ID=$(az ad group show -g "TKT-Philippines-AVD-Users" --query id -o tsv)

az role assignment create \
    --assignee "$GROUP_ID" \
    --role "Virtual Machine User Login" \
    --scope "/subscriptions/YOUR_SUB_ID/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.Compute/virtualMachines/vm-tktph-01"

az role assignment create \
    --assignee "$GROUP_ID" \
    --role "Virtual Machine User Login" \
    --scope "/subscriptions/YOUR_SUB_ID/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.Compute/virtualMachines/vm-tktph-02"

# 4. Restart VMs
az vm restart -g rg-tktph-avd-prod-sea -n vm-tktph-01 --no-wait
az vm restart -g rg-tktph-avd-prod-sea -n vm-tktph-02 --no-wait
```

**Verify:**
```bash
# Wait 3-5 minutes, then check
az desktopvirtualization sessionhost list \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --query "[].{Name:name, Status:status}" -o table
```

---

### Option B: Fresh Deployment

Delete existing resources and redeploy with V6.2.

**Time:** ~25 minutes  
**Downtime:** Full redeployment

```bash
# 1. Delete resource group (WARNING: destroys all data)
az group delete --name rg-tktph-avd-prod-sea --yes --no-wait

# 2. Wait for deletion
az group wait --name rg-tktph-avd-prod-sea --deleted

# 3. Run V6.2 deployment
bash scripts/deploy-avd-platform.sh
```

**Note:** This will delete FSLogix profiles. Back up important data first.

---

## Script Changes Summary

### deploy-avd-platform.sh

**VM Creation (Line ~720):**
```bash
# V4/V5
az vm create ... --output none

# V6.2
az vm create ... --assign-identity --output none
```

**New Extension (After VM creation):**
```bash
# V6.2 adds
az vm extension set \
    --name "AADLoginForWindows" \
    --publisher "Microsoft.Azure.ActiveDirectory" \
    --version "2.0"
```

**DSC Settings:**
```json
// V4/V5
"properties": {
    "hostPoolName": "...",
    "registrationInfoToken": "..."
}

// V6.2
"properties": {
    "hostPoolName": "...",
    "registrationInfoToken": "...",
    "aadJoin": true
}
```

**New RBAC (After user creation):**
```bash
# V6.2 adds
az role assignment create \
    --role "Virtual Machine User Login" \
    --scope "/path/to/vm"
```

---

## Rollback Procedure

If V6.2 causes issues:

1. The AADLoginForWindows extension can be removed:
```bash
az vm extension delete \
    --resource-group rg-tktph-avd-prod-sea \
    --vm-name vm-tktph-01 \
    --name "AADLoginForWindows"
```

2. However, this will break user login. The recommended approach is to:
   - Keep V6.2 configuration
   - Report issues for investigation

---

## Verification Checklist

After migration, verify:

- [ ] Session hosts show "Available" status
- [ ] Users can see workspace at rdweb.wvd.microsoft.com
- [ ] Users can connect to SessionDesktop
- [ ] MFA prompts work correctly
- [ ] FSLogix profiles load

---

## Support

Contact: tom.tuerlings@tktconsulting.com

---

*Migration Guide Version: 6.2 | February 13, 2026*
