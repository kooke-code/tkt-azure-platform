# Known Issues - TKT Philippines AVD Platform

**Version:** 6.2  
**Last Updated:** February 13, 2026

---

## Resolved in V6.2

### ✅ RESOLVED: Session Hosts Show "Unavailable" - DomainJoinedCheck Failed

**Symptoms:**
- Session hosts status: "Unavailable"
- Health check: `DomainJoinedCheck: HealthCheckFailed`
- Error: "SessionHost is not joined to a domain"

**Root Cause:**
VMs were created without Entra ID join configuration. For cloud-only AVD (no on-premises AD), VMs require:
- System-assigned managed identity
- AADLoginForWindows extension
- aadJoin parameter in DSC configuration

**Resolution (V6.2):**
The `deploy-avd-platform.sh` script now includes:
```bash
az vm create ... --assign-identity
az vm extension set ... --name "AADLoginForWindows"
DSC settings: "aadJoin": true
```

**Fix for existing deployments:**
```bash
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea
```

---

### ✅ RESOLVED: Users Can See Workspace But Can't Connect

**Symptoms:**
- Users see "TKT Philippines Workspace" in web client
- Clicking "SessionDesktop" fails with permission error

**Root Cause:**
Missing `Virtual Machine User Login` RBAC role on session host VMs.

**Resolution (V6.2):**
Script now assigns both required roles:
- `Desktop Virtualization User` on application group
- `Virtual Machine User Login` on each VM

---

## Current Known Issues

### ⚠️ DSv5 VM Quota Not Available in Southeast Asia

**Impact:** Medium  
**Workaround:** Use Standard_D4s_v3 instead

**Details:**
DSv5 family VMs have zero quota in Southeast Asia region by default. The deployment script now includes interactive VM size selection with quota checking.

**To request quota:**
1. Azure Portal → Subscriptions → Usage + quotas
2. Request quota increase for "Standard DSv5 Family vCPUs"

---

### ⚠️ Azure CLI "Content Already Consumed" Error

**Impact:** Low  
**Workaround:** Upgrade to Azure CLI 2.83.0+

**Details:**
Azure CLI versions before 2.83.0 have a bug that can cause "content already consumed" errors during deployment.

**Fix:**
```bash
az upgrade
```

---

### ⚠️ FSLogix Profile Container Size

**Impact:** Low  
**Workaround:** Monitor storage usage

**Details:**
FSLogix profiles can grow large with extensive user data. Default 100GB share may fill up with heavy usage.

**Monitoring:**
```bash
az storage share stats --name profiles --account-name sttktphfslogix
```

---

### ⚠️ Session Host Health Check Timing

**Impact:** Low  
**Workaround:** Wait 3-5 minutes after deployment

**Details:**
After VM restart, session hosts may show "Unavailable" for 2-5 minutes while:
- Entra ID join completes
- AVD agent registers
- Health checks run

**Verification:**
```bash
az desktopvirtualization sessionhost list \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --query "[].{Name:name, Status:status}" -o table
```

---

## Reporting New Issues

Please report issues with:
1. Error message (full text)
2. Command that failed
3. Azure CLI version (`az --version`)
4. Steps to reproduce

Contact: tom.tuerlings@tktconsulting.com

---

## Version History

| Version | Issues Resolved |
|---------|-----------------|
| 6.2 | Entra ID join, VM login RBAC |
| 5.0 | Validation improvements |
| 4.0 | Initial release |

---

*Last updated: February 13, 2026*
