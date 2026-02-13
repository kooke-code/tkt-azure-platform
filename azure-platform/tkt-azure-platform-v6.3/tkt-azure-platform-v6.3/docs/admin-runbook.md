# TKT Philippines AVD - Administrator Runbook

**Version:** 6.2  
**Domain:** tktconsulting.be

---

## Quick Reference

### URLs

| Resource | URL |
|----------|-----|
| Azure Portal | https://portal.azure.com |
| AVD Management | https://portal.azure.com/#view/Microsoft_Azure_WVD |
| Entra ID | https://entra.microsoft.com |
| User Web Client | https://rdweb.wvd.microsoft.com/arm/webclient |

### Resource Names

| Component | Name |
|-----------|------|
| Resource Group | rg-tktph-avd-prod-sea |
| Host Pool | tktph-hp |
| Workspace | tktph-ws |
| Application Group | tktph-dag |
| Storage Account | sttktphfslogix |
| Security Group | TKT-Philippines-AVD-Users |

### VMs

| VM | IP | Size |
|----|-----|------|
| vm-tktph-01 | 10.2.1.4 | Standard_D4s_v3 |
| vm-tktph-02 | 10.2.1.5 | Standard_D4s_v3 |

---

## User Management

### Add User

```bash
# Create user
az ad user create \
    --display-name "PH Consultant 005" \
    --user-principal-name "ph-consultant-005@tktconsulting.be" \
    --password "TempPassword123!" \
    --force-change-password-next-sign-in true

# Add to security group
USER_ID=$(az ad user show --id "ph-consultant-005@tktconsulting.be" --query id -o tsv)
az ad group member add --group "TKT-Philippines-AVD-Users" --member-id "$USER_ID"
```

### Remove User

```bash
USER_ID=$(az ad user show --id "ph-consultant-005@tktconsulting.be" --query id -o tsv)
az ad group member remove --group "TKT-Philippines-AVD-Users" --member-id "$USER_ID"
az ad user update --id "ph-consultant-005@tktconsulting.be" --account-enabled false
```

### Reset Password

```bash
az ad user update \
    --id "ph-consultant-001@tktconsulting.be" \
    --password "NewTempPass123!" \
    --force-change-password-next-sign-in true
```

### List Users

```bash
az ad group member list --group "TKT-Philippines-AVD-Users" \
    --query "[].{Name:displayName, UPN:userPrincipalName}" -o table
```

---

## Session Host Management

### Check Status

```bash
az desktopvirtualization sessionhost list \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --query "[].{Name:name, Status:status, Sessions:sessions}" -o table
```

### Drain Mode

```bash
# Enable (prevent new sessions)
az desktopvirtualization sessionhost update \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --name "vm-tktph-01" \
    --allow-new-session false

# Disable (allow sessions)
az desktopvirtualization sessionhost update \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --name "vm-tktph-01" \
    --allow-new-session true
```

### View Active Sessions

```bash
az desktopvirtualization user-session list \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --query "[].{User:userPrincipalName, State:sessionState}" -o table
```

### Restart VM

```bash
az vm restart -g rg-tktph-avd-prod-sea -n vm-tktph-01
```

### Start/Stop VMs

```bash
# Start
az vm start -g rg-tktph-avd-prod-sea -n vm-tktph-01

# Stop (deallocate)
az vm deallocate -g rg-tktph-avd-prod-sea -n vm-tktph-01
```

---

## Troubleshooting

### Session Host "Unavailable"

**Cause:** Entra ID join not configured

**Fix:**
```bash
# Run fix script
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea

# Or manually:
az vm identity assign -g rg-tktph-avd-prod-sea -n vm-tktph-01

az vm extension set \
    --resource-group rg-tktph-avd-prod-sea \
    --vm-name vm-tktph-01 \
    --name "AADLoginForWindows" \
    --publisher "Microsoft.Azure.ActiveDirectory" \
    --version "2.0"

az vm restart -g rg-tktph-avd-prod-sea -n vm-tktph-01
```

### User Can't See Workspace

**Cause:** Missing Desktop Virtualization User role

**Fix:**
```bash
GROUP_ID=$(az ad group show -g "TKT-Philippines-AVD-Users" --query id -o tsv)
SUB_ID=$(az account show --query id -o tsv)

az role assignment create \
    --assignee "$GROUP_ID" \
    --role "Desktop Virtualization User" \
    --scope "/subscriptions/$SUB_ID/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.DesktopVirtualization/applicationGroups/tktph-dag"
```

### User Can't Connect (sees workspace)

**Cause:** Missing VM User Login role

**Fix:**
```bash
GROUP_ID=$(az ad group show -g "TKT-Philippines-AVD-Users" --query id -o tsv)

az role assignment create \
    --assignee "$GROUP_ID" \
    --role "Virtual Machine User Login" \
    --scope "/subscriptions/$SUB_ID/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.Compute/virtualMachines/vm-tktph-01"

az role assignment create \
    --assignee "$GROUP_ID" \
    --role "Virtual Machine User Login" \
    --scope "/subscriptions/$SUB_ID/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.Compute/virtualMachines/vm-tktph-02"
```

### Check Health Details

```bash
az desktopvirtualization sessionhost show \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --name "vm-tktph-01" \
    --query "sessionHostHealthCheckResults" -o json
```

---

## Maintenance

### Weekly
- [ ] Check session host health
- [ ] Review Log Analytics for errors
- [ ] Verify user connectivity

### Monthly
- [ ] Apply Windows updates
- [ ] Review costs vs budget
- [ ] Audit user accounts

### Quarterly
- [ ] Test disaster recovery
- [ ] Review capacity needs
- [ ] Update documentation

---

## Transfer Ownership

To transfer to tom.tuerlings@tktconsulting.com:

```bash
bash scripts/transfer-ownership.sh
```

This assigns:
- Owner on resource group
- Contributor on subscription
- Owner of security group
- Alert email recipient

---

*Runbook Version: 6.2 | February 13, 2026*
