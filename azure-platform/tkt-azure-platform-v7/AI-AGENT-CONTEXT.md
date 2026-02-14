# AI Agent Context - TKT Philippines AVD Platform V7

This document provides context for AI assistants working on this project.

## Project Overview

**Project:** TKT Consulting Philippines Azure Virtual Desktop Platform  
**Version:** 7.0 (Consolidation Release)  
**Last Updated:** February 14, 2026  
**Owner:** tom.tuerlings@tktconsulting.com

## V7 Note

V7 consolidates all files from V3 through V6.3 into one complete package. Files previously lost between versions (cost optimization docs, governance framework, VM hardening script, customer template, etc.) have been restored. The deploy script includes all V6.2 and V6.3 critical fixes (Entra ID join, stale device cleanup, Teams/Office installation). All scripts are macOS bash 3.2 compatible.

## Architecture Summary

| Component | Value |
|-----------|-------|
| Platform | Azure Virtual Desktop (AVD) |
| Region | Southeast Asia |
| Join Type | **Microsoft Entra ID (cloud-only)** |
| Domain | tktconsulting.be |
| Session Hosts | 2x Standard_D4s_v3 (Windows 11 Multi-session) |
| Max Users | 8 concurrent (4 per host) |
| Profile Storage | FSLogix on Azure Files Premium |
| Monthly Cost | ~€235 |

## Key Changes in V6.2

| Issue | Root Cause | Fix Applied |
|-------|------------|-------------|
| Session hosts "Unavailable" | VMs not Entra ID joined | Added AADLoginForWindows extension |
| DomainJoinedCheck failed | No domain/Entra join configured | Added `--assign-identity` and `aadJoin: true` |
| Users couldn't log in | Missing VM RBAC | Added "Virtual Machine User Login" role |

## Critical Configuration Points

### Entra ID Join Requirements (V6.2)
For cloud-only AVD (no on-premises AD), VMs require:
1. **System-assigned managed identity** - `az vm create --assign-identity`
2. **AADLoginForWindows extension** - Enables Entra ID authentication
3. **aadJoin parameter in DSC** - Tells AVD agent to use Entra ID
4. **Virtual Machine User Login role** - RBAC for user authentication

### User Authentication Flow
```
User → rdweb.wvd.microsoft.com → Entra ID Auth → AVD Gateway → Session Host (Entra ID joined)
```

## Resource Naming Convention

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| Resource Group | rg-{project}-avd-prod-{region} | rg-tktph-avd-prod-sea |
| Virtual Network | vnet-{project}-avd-{region} | vnet-tktph-avd-sea |
| Subnet | snet-avd | snet-avd |
| NSG | nsg-{project}-avd | nsg-tktph-avd |
| Storage Account | st{project}fslogix | sttktphfslogix |
| Host Pool | {project}-hp | tktph-hp |
| Workspace | {project}-ws | tktph-ws |
| App Group | {project}-dag | tktph-dag |
| VMs | vm-{project}-{nn} | vm-tktph-01, vm-tktph-02 |
| Log Analytics | law-{project}-avd-{region} | law-tktph-avd-sea |

## File Structure

```
tkt-azure-platform-v6.2/
├── README.md                    # Main documentation
├── AI-AGENT-CONTEXT.md          # This file
├── docs/
│   ├── architecture.md          # Detailed architecture
│   ├── admin-runbook.md         # Operations guide
│   └── user-guide.md            # End user instructions
├── scripts/
│   ├── deploy-avd-platform.sh   # Main deployment (V6.2)
│   ├── validate-deployment.sh   # Validation checks
│   ├── fix-entra-id-join.sh     # Fix existing VMs
│   ├── transfer-ownership.sh    # Ownership transfer
│   └── Setup-ConditionalAccess.ps1  # CA policies
└── templates/
    ├── avd-config.json          # Configuration parameters
    └── conditional-access.json  # CA policy templates
```

## Deployment Commands

### Fresh Deployment
```bash
bash scripts/deploy-avd-platform.sh
```

### Fix Existing Deployment (Entra ID Join)
```bash
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea
```

### Validate
```bash
bash scripts/validate-deployment.sh --resource-group rg-tktph-avd-prod-sea --host-pool tktph-hp
```

## Common Issues & Solutions

### Issue: Session hosts show "Unavailable"
**Cause:** Entra ID join not configured  
**Solution:** Run `fix-entra-id-join.sh` or redeploy with V6.2 script

### Issue: Users can't see workspace
**Cause:** Missing Desktop Virtualization User role  
**Solution:** Assign role to security group on application group

### Issue: Users see workspace but can't connect
**Cause:** Missing Virtual Machine User Login role  
**Solution:** Assign role to security group on VMs

### Issue: Health check shows DomainJoinedCheck failed
**Cause:** VM not joined to Entra ID  
**Solution:** Install AADLoginForWindows extension + restart VM

## Environment Variables

The deployment script accepts these environment variables:

```bash
# Required
ADMIN_PASSWORD="..."           # VM admin password
USER_PASSWORD="..."            # User temporary password

# Optional (have defaults)
RESOURCE_GROUP="rg-tktph-avd-prod-sea"
LOCATION="southeastasia"
ENTRA_DOMAIN="tktconsulting.be"
VM_SIZE="Standard_D4s_v3"
VM_COUNT="2"
USER_COUNT="4"
ALERT_EMAIL="tom.tuerlings@tktconsulting.com"
```

## Conditional Access

Policies allow access from:
- ✅ Philippines (PH) - Consultants
- ✅ Belgium (BE) - Administrators

Policies require:
- MFA for all sessions
- Block legacy authentication
- 8-hour sign-in frequency

## Cost Breakdown

| Component | Monthly |
|-----------|---------|
| 2x D4s_v3 VMs | €190 |
| Premium Storage (100GB) | €20 |
| Log Analytics | €15 |
| Networking | €10 |
| **Total** | **€235** |

## Support Contacts

| Role | Contact |
|------|---------|
| Platform Owner | tom.tuerlings@tktconsulting.com |
| Repository | github.com/kooke-code/tkt-azure-platform |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.0 | 2026-02-12 | Initial automated deployment |
| 5.0 | 2026-02-13 | Bug fixes, validation improvements |
| 6.2 | 2026-02-13 | **Entra ID join fix**, VM login RBAC, managed identity |
