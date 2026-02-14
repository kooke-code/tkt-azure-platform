# Known Issues - TKT Philippines AVD Platform

**Version:** 6.3  
**Last Updated:** February 13, 2026

---

## Resolved in V6.3

### ✅ RESOLVED: Session Hosts "Unavailable" After Entra ID Join

**Symptoms:**
- Session hosts status: "Unavailable"
- Health check: `DomainJoinedCheck: HealthCheckFailed` (expected for cloud-only)
- Health check: `AADJoinedHealthCheck: HealthCheckSucceeded` but host still unavailable

**Root Cause:**
Host pool missing `targetisaadjoined:i:1` RDP property. This property tells the RDP client that the session host is Entra ID joined, not domain joined.

**Resolution (V6.3):**
```bash
az desktopvirtualization hostpool create ... --custom-rdp-property "targetisaadjoined:i:1"
```

**Fix for existing deployments:**
```bash
az rest --method PATCH \
    --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.DesktopVirtualization/hostPools/{hp}?api-version=2024-04-03" \
    --body '{"properties":{"customRdpProperty":"targetisaadjoined:i:1"}}'
```

---

### ✅ RESOLVED: Entra ID Join Fails with "hostname_duplicate"

**Symptoms:**
- AADLoginForWindows extension installed but VM not joined
- Extension logs show: `error_hostname_duplicate`
- Error: "Another object with the same value for property hostnames already exists"

**Root Cause:**
Stale Entra ID device records from previous VM deployments with the same hostname.

**Resolution (V6.3):**
Script now cleans up stale devices before VM creation:
```bash
DEVICE_ID=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq '${VM_NAME}'" --query "value[0].id" -o tsv)
if [ -n "$DEVICE_ID" ]; then
    az rest --method DELETE --url "https://graph.microsoft.com/v1.0/devices/${DEVICE_ID}"
fi
```

---

### ✅ RESOLVED: Teams Not Optimized for AVD

**Symptoms:**
- Teams installed but video/audio uses host processing
- High CPU usage during Teams calls
- Poor call quality

**Root Cause:**
Missing WebRTC Redirector and `IsWVDEnvironment` registry key.

**Resolution (V6.3):**
Phase 4.5 now installs:
1. WebRTC Redirector (`https://aka.ms/msrdcwebrtcsvc/msi`)
2. Registry key: `HKLM:\SOFTWARE\Microsoft\Teams\IsWVDEnvironment = 1`

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

### ⚠️ Double Authentication Prompt for Entra ID Join

**Impact:** Low (UX only)  
**Status:** Expected behavior

**Details:**
Users connecting to Entra ID joined session hosts see two login prompts:
1. First prompt: AVD web client authentication
2. Second prompt: Windows login to the VM

**Workaround:**
This is expected for Entra ID joined VMs. Single Sign-On (SSO) can be configured with Conditional Access, but requires Entra ID P1/P2 licensing.

---

### ⚠️ DSv5 VM Quota Not Available in Southeast Asia

**Impact:** Medium  
**Workaround:** Use Standard_D4s_v3 or D4s_v4 instead

**Details:**
DSv5 family VMs have zero quota in Southeast Asia region by default. The deployment script includes interactive VM size selection with quota checking.

**To request quota:**
1. Azure Portal → Subscriptions → Usage + quotas
2. Request quota increase for "Standard DSv5 Family vCPUs"

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

### ⚠️ Microsoft 365 License Required for Teams

**Impact:** Medium  
**Workaround:** Assign M365 Business Premium licenses to users

**Details:**
Teams is installed by Phase 4.5 but requires a Microsoft 365 license for full functionality (chat, meetings, etc.).

**Verification:**
1. Microsoft 365 Admin Center → Users
2. Ensure each user has M365 Business Premium assigned

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
| 6.3 | targetisaadjoined RDP property, hostname_duplicate, Teams optimization |
| 6.2 | Entra ID join, VM login RBAC |
| 5.0 | Validation improvements |
| 4.0 | Initial release |

---

*Last updated: February 13, 2026*
