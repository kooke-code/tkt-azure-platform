# V4 Architecture Notes

**Version:** 4.0  
**Date:** 2026-02-12  
**Status:** Production Ready

---

## Overview

V4 is a fully automated deployment of the TKT Philippines AVD Platform. It maintains the same architecture as V3 but adds complete automation for hands-off deployment.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Azure (Southeast Asia Region)                         │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                Resource Group: rg-tktph-avd                       │  │
│  │                                                                    │  │
│  │  ┌─────────────────┐    ┌─────────────────┐                       │  │
│  │  │   VNet          │    │  Storage Acc    │                       │  │
│  │  │  10.2.0.0/16    │    │  Premium Files  │                       │  │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │                       │  │
│  │  │  │ Subnet    │  │    │  │ profiles  │  │ ◄── FSLogix          │  │
│  │  │  │ .1.0/24   │  │    │  │ share     │  │                       │  │
│  │  │  └───────────┘  │    │  └───────────┘  │                       │  │
│  │  └─────────────────┘    └─────────────────┘                       │  │
│  │           │                      │                                 │  │
│  │           │    SMB 445           │                                 │  │
│  │           ▼                      │                                 │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │                   Session Hosts (2x)                         │  │  │
│  │  │  ┌──────────────┐    ┌──────────────┐                       │  │  │
│  │  │  │  tktph-sh-01 │    │  tktph-sh-02 │                       │  │  │
│  │  │  │  D4s_v5      │    │  D4s_v5      │                       │  │  │
│  │  │  │  Win11 AVD   │    │  Win11 AVD   │                       │  │  │
│  │  │  │  FSLogix     │    │  FSLogix     │                       │  │  │
│  │  │  └──────────────┘    └──────────────┘                       │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                              │                                     │  │
│  │                              │ AVD Agent                           │  │
│  │                              ▼                                     │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │                 AVD Control Plane                            │  │  │
│  │  │  ┌──────────┐  ┌───────────┐  ┌─────────────────┐          │  │  │
│  │  │  │Workspace │  │ Host Pool │  │ Application     │          │  │  │
│  │  │  │tktph-ws  │──│ tktph-hp  │──│ Group (Desktop) │          │  │  │
│  │  │  └──────────┘  │ Pooled    │  └─────────────────┘          │  │  │
│  │  │                │ Breadth   │                                │  │  │
│  │  │                └───────────┘                                │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                    │  │
│  │  ┌─────────────────┐                                              │  │
│  │  │  Log Analytics  │ ◄── Diagnostics                              │  │
│  │  │  90-day retain  │                                              │  │
│  │  └─────────────────┘                                              │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘

        │                              ▲
        │ RDP/HTTPS                    │ Entra ID Auth + MFA
        ▼                              │
┌─────────────────┐           ┌─────────────────┐
│  Philippines    │           │   Entra ID      │
│  Consultants    │◄──────────│   + Cond Access │
│  (4 users)      │           │   + M365 BP     │
└─────────────────┘           └─────────────────┘
```

## V3 to V4 Changes

### What Changed

| Aspect | V3 | V4 |
|--------|----|----|
| Deployment Method | Semi-manual (scripts + portal) | Fully automated (single script) |
| User Creation | Manual in Entra portal | Automated via Graph API |
| FSLogix Setup | Manual installation | Automated via run-command |
| Validation | Manual checking | Automated smoke tests |
| Documentation | Separate process | Auto-generated report |

### What Stayed the Same

- **Network Architecture:** VNet 10.2.0.0/16, Subnet 10.2.1.0/24
- **VM Specification:** Standard_D4s_v5 (4 vCPU, 16GB RAM)
- **Operating System:** Windows 11 Enterprise 23H2 AVD
- **Storage:** Premium FileStorage, 100GB FSLogix share
- **AVD Configuration:** Pooled, BreadthFirst, 4 max sessions
- **Security:** NSG-only (no Azure Firewall), MFA required
- **Monitoring:** Log Analytics with 90-day retention
- **Region:** Southeast Asia

### Removed from V4

- **Azure Firewall:** Removed for cost optimization (NSG sufficient for this use case)
- **Azure Bastion:** Removed (RDP via public IP with NSG restriction)
- **Windows Server:** Switched to Windows 11 AVD image (better user experience)

### New in V4

- **Dry-run mode:** Preview deployment without making changes
- **Idempotent scripts:** Safe to run multiple times
- **VM Schedule:** Optional auto start/stop (07:00-18:00 Brussels time, Mon-Fri)
- **Session Logging:** Activity logging to Log Analytics (optional Teramind video)
- **Validation suite:** 20+ automated tests
- **Deployment report:** Auto-generated markdown/JSON

## Security Architecture

### Network Security

```
NSG Rules (Inbound):
┌─────────────────────────────────────────────────────────────┐
│ Priority │ Name                │ Source          │ Port    │
├──────────┼────────────────────┼─────────────────┼─────────┤
│ 100      │ AllowAVDService    │ WindowsVirtual  │ 443     │
│          │                    │ Desktop (tag)   │         │
│ 110      │ AllowAzureCloud    │ AzureCloud      │ 443     │
│ 120      │ AllowKMS           │ Internet        │ 1688    │
│ 130      │ AllowDNS           │ Internet        │ 53      │
│ 200      │ AllowRDP-Admin     │ [Admin IPs]     │ 3389    │
│ 4096     │ DenyAll            │ *               │ *       │
└─────────────────────────────────────────────────────────────┘
```

### Identity Security

- **Authentication:** Entra ID (cloud-only accounts)
- **MFA:** Required via Conditional Access policy
- **Session Control:** 8-hour timeout
- **RBAC:** Desktop Virtualization User role only

### Session Host Hardening

| Control | Setting | Implementation |
|---------|---------|----------------|
| USB Storage | Blocked | Registry + Group Policy |
| Clipboard | Inbound only | RDP restrictions |
| Drive Redirection | Disabled | RDP restrictions |
| Printer Redirection | Disabled | RDP restrictions |
| Local Storage | Disabled | Folder redirection to Azure Files |
| Windows Defender | Enabled | Real-time + Cloud protection |
| Audit Logging | Enabled | Process, logon, file events |

## Cost Breakdown

### Monthly Estimate (€220)

| Component | Specification | Cost (€) |
|-----------|--------------|----------|
| Session Host VMs (2x) | D4s_v5 | 190 |
| Premium Storage | FileStorage 100GB | 20 |
| Log Analytics | ~5GB/month | 5 |
| Networking | PIPs, bandwidth | 5 |
| **Total** | | **€220** |

### Cost Optimization Applied

| Optimization | Savings | Status |
|--------------|---------|--------|
| No Azure Firewall | €125/month | ✅ Applied |
| No Azure Bastion | €140/month | ✅ Applied |
| VM scheduling (07:00-18:00 Brussels) | €95/month | ⏳ Optional |
| Windows 11 AVD (no RDS CAL) | €50/month | ✅ Applied |

**V3 Projected Cost:** €1,487/month  
**V4 Actual Cost:** €220/month  
**Savings:** 85%

## Deployment Phases

### Phase 1: Networking
- Resource group creation
- VNet and subnet deployment
- NSG with AVD service rules
- Tags application

### Phase 2: Storage & Monitoring
- Premium FileStorage account
- FSLogix profiles share (100GB)
- Log Analytics workspace (90-day retention)
- Action group for alerts

### Phase 3: AVD Control Plane
- Workspace creation
- Host pool (Pooled, BreadthFirst)
- Desktop application group
- Registration token generation
- Diagnostics configuration

### Phase 4: Session Hosts
- VM deployment (Windows 11 AVD)
- AVD agent installation
- Security hardening (USB blocked, RDP restricted)
- Monitoring agent installation

### Phase 5: Identity
- Entra ID user creation (4 accounts)
- Security group creation
- M365 Business Premium license assignment
- Conditional Access policy (MFA)
- App group role assignment

### Phase 6: Validation & Reporting
- 20+ automated validation tests
- Connectivity verification
- FSLogix profile testing
- Deployment report generation

## Optional Features (Post-Deployment)

### VM Schedule (setup-vm-schedule.sh)
Adds automatic start/stop to reduce costs:
- **Start:** 07:00 Brussels time (CET/CEST), Mon-Fri
- **Stop:** 18:00 Brussels time (CET/CEST), Mon-Fri
- **Weekends:** VMs remain stopped
- **Cost:** ~€5/month for Automation Account
- **Savings:** ~€95/month (50% VM runtime reduction)

### Session Logging (setup-session-logging.sh)
Adds activity tracking for compliance/auditing:
- **Windows Event Logging:** Login/logout, apps launched, files accessed, PowerShell commands
- **Log Analytics Integration:** 90-day retention, KQL queryable
- **Optional Teramind:** Full video session recording (~€25/user/month, separate subscription)

## Files Structure

```
tkt-azure-platform-v4/
├── scripts/
│   ├── deploy-avd-platform-v4.sh      # Main orchestrator (6 phases)
│   ├── setup-session-host-hardening.sh # VM hardening
│   ├── setup-entra-id-automation.sh   # Identity setup
│   ├── setup-fslogix-profiles.sh      # FSLogix config
│   ├── setup-vm-schedule.sh           # Auto start/stop (Brussels time)
│   ├── setup-session-logging.sh       # Activity logging
│   ├── validate-deployment.sh         # Smoke tests
│   └── generate-deployment-report.sh  # Reporting
├── docs/
│   ├── v4-architecture-notes.md       # This file
│   ├── v4-known-issues.md             # Known limitations
│   ├── v4-migration-guide.md          # Migration steps
│   └── TESTING.md                     # Testing guide
├── templates/
│   ├── graph-api-user-template.json   # User creation template
│   ├── conditional-access-policy.json # CA policy definition
│   └── deployment-report-template.md  # Report template
└── AI-AGENT-CONTEXT.md                # Prompt context for AI assistants
```

## Decision Log

| Decision | Rationale | Alternative Considered |
|----------|-----------|------------------------|
| Windows 11 AVD | Better UX, no RDS CAL needed | Windows Server 2022 |
| Pooled host pool | Cost sharing, simple scaling | Personal desktops |
| BreadthFirst load balancing | Even distribution | DepthFirst |
| Premium FileStorage | Low latency for FSLogix | Standard storage |
| NSG-only (no Firewall) | Cost optimization | Azure Firewall |
| 2 session hosts | Redundancy, 4 users | Single host |

## References

- [Azure Virtual Desktop Documentation](https://learn.microsoft.com/azure/virtual-desktop/)
- [FSLogix Documentation](https://learn.microsoft.com/fslogix/)
- [Azure Naming Conventions](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [V3 Deployment Transcript](../transcripts/)
