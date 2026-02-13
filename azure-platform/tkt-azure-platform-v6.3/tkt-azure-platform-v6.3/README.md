# TKT Philippines AVD Platform V6.3

Fully automated Azure Virtual Desktop deployment for SAP consultants

![version](https://img.shields.io/badge/version-6.3-blue)
![Azure](https://img.shields.io/badge/Azure-AVD-0078D4)
![cost](https://img.shields.io/badge/cost-€235%2Fmonth-green)
![join](https://img.shields.io/badge/join-Entra%20ID-orange)

---

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/kooke-code/tkt-azure-platform.git
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v6.3

# Deploy (interactive prompts for passwords)
bash scripts/deploy-avd-platform.sh

# Validate deployment (comprehensive - auto-discovers resources)
bash scripts/validate-deployment-comprehensive.sh

# Or use basic validation with explicit parameters
bash scripts/validate-deployment.sh --resource-group rg-tktph-avd-prod-sea --host-pool tktph-hp
```

---

## ✨ What's New in V6.3

| Feature | Description |
|---------|-------------|
| 🔴 **Critical Fix** | Added `targetisaadjoined:i:1` RDP property to host pool |
| 🔴 **Critical Fix** | Stale Entra ID device cleanup before VM creation |
| 📦 **Teams** | Automated Teams installation with WebRTC Redirector |
| 📦 **Office** | Microsoft 365 Apps with shared computer licensing |
| ✅ **Validation** | Comprehensive validation script (50+ checks, auto-discovery) |

### V6.3 Fixes Critical Issues
- **Session hosts stuck "Unavailable"** - Now adds `targetisaadjoined:i:1` to host pool
- **Entra ID join "hostname_duplicate"** - Cleans up stale devices before VM creation
- **Teams not optimized** - Installs WebRTC Redirector + sets `IsWVDEnvironment` registry

---

## 📋 Prerequisites

- Azure CLI v2.83+ (`az login` completed)
- Contributor role on Azure subscription
- User Administrator role in Entra ID
- Bash shell (not zsh)
- Verified domain: `tktconsulting.be`

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                 Azure (Southeast Asia)                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │            rg-tktph-avd-prod-sea                          │  │
│  │                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │  │
│  │  │ vm-tktph-01 │  │ vm-tktph-02 │  │ sttktphfslogix  │   │  │
│  │  │  D4s_v3     │  │  D4s_v3     │  │ FSLogix Profiles│   │  │
│  │  │ Entra Join  │  │ Entra Join  │  │ 100GB Premium   │   │  │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────────┘   │  │
│  │         │                │                                │  │
│  │         └────────┬───────┘                                │  │
│  │                  │                                        │  │
│  │  ┌───────────────┴────────────────────────────────────┐  │  │
│  │  │              AVD Control Plane                      │  │  │
│  │  │  tktph-ws │ tktph-hp │ tktph-dag                   │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                   https://rdweb.wvd.microsoft.com
```

---

## 📁 File Structure

```
tkt-azure-platform-v6.2/
├── README.md                    # This file
├── AI-AGENT-CONTEXT.md          # AI assistant context
├── docs/
│   ├── architecture.md          # Detailed architecture
│   ├── architecture-notes.md    # Technical notes
│   ├── admin-runbook.md         # Operations guide
│   ├── user-guide.md            # End user guide
│   ├── known-issues.md          # Known issues & fixes
│   ├── migration-guide.md       # V4/V5 → V6.2 migration
│   └── TESTING.md               # Testing procedures
├── scripts/
│   ├── deploy-avd-platform.sh          # Main deployment (V6.2)
│   ├── validate-deployment.sh          # Validation checks
│   ├── fix-entra-id-join.sh            # Fix Entra ID join
│   ├── provision-avd-users.sh          # User provisioning
│   ├── setup-avd-alerts.sh             # Monitoring alerts
│   ├── setup-entra-id-automation.sh    # Entra ID setup
│   ├── setup-fslogix-profiles.sh       # FSLogix profiles
│   ├── setup-session-host-hardening.sh # VM hardening
│   ├── setup-session-logging.sh        # Session logging
│   ├── setup-vm-schedule.sh            # Auto start/stop
│   ├── generate-deployment-report.sh   # Reporting
│   ├── transfer-ownership.sh           # Ownership transfer
│   └── Setup-ConditionalAccess.ps1     # CA policies
├── templates/
│   ├── avd-config.json                 # Configuration
│   ├── conditional-access.json         # CA templates
│   ├── deployment-report-template.md   # Report template
│   ├── graph-api-user-template.json    # Graph API template
│   └── user-provisioning-intake.json   # User intake
└── CHANGELOG.md                        # Version history (NEW in V6.3)
```

### Script Summary

| Script | Purpose |
|--------|---------|
| `deploy-avd-platform.sh` | Main deployment (6 phases + Phase 4.5 apps) |
| `validate-deployment-comprehensive.sh` | **NEW** - 50+ checks, auto-discovery |
| `validate-deployment.sh` | Basic validation with manual parameters |
| `fix-entra-id-join.sh` | Fix existing VMs with join issues |
| `provision-avd-users.sh` | Bulk user creation |
| `setup-fslogix-profiles.sh` | Profile container setup |
| `setup-vm-schedule.sh` | Auto start/stop scheduling |

---

## 🔧 Configuration

### Default Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| RESOURCE_GROUP | rg-tktph-avd-prod-sea | Resource group name |
| LOCATION | southeastasia | Azure region |
| ENTRA_DOMAIN | tktconsulting.be | User domain |
| VM_SIZE | Standard_D4s_v3 | Session host size |
| VM_COUNT | 2 | Number of session hosts |
| MAX_SESSION_LIMIT | 4 | Max users per host |
| USER_COUNT | 4 | Consultant accounts |

### Override with Environment Variables

```bash
export VM_SIZE="Standard_D4s_v5"
export VM_COUNT="3"
bash scripts/deploy-avd-platform.sh
```

---

## 👥 User Access

**Web Client:** https://rdweb.wvd.microsoft.com/arm/webclient

**User Accounts:**
| Username | Display Name |
|----------|--------------|
| ph-consultant-001@tktconsulting.be | PH Consultant 001 |
| ph-consultant-002@tktconsulting.be | PH Consultant 002 |
| ph-consultant-003@tktconsulting.be | PH Consultant 003 |
| ph-consultant-004@tktconsulting.be | PH Consultant 004 |

---

## 🔒 Security

### Conditional Access Policies
- ✅ MFA required for all sessions
- ✅ Access allowed from Philippines and Belgium only
- ✅ Legacy authentication blocked
- ✅ 8-hour sign-in frequency

### Deploy Conditional Access
```powershell
# PowerShell (report-only mode)
.\scripts\Setup-ConditionalAccess.ps1

# Enforce after testing
.\scripts\Setup-ConditionalAccess.ps1 -ReportOnlyMode $false
```

---

## 💰 Cost Breakdown

| Component | Monthly Cost |
|-----------|-------------|
| 2x D4s_v3 VMs (730 hrs) | €190 |
| Premium FileStorage (100GB) | €20 |
| Log Analytics (~5GB) | €15 |
| Networking | €10 |
| **Total** | **€235** |

---

## 🛠️ Troubleshooting

### Session hosts "Unavailable"
```bash
# Fix Entra ID join on existing VMs
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea
```

### Check session host status
```bash
az desktopvirtualization sessionhost list \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool-name tktph-hp \
    --query "[].{Name:name, Status:status}" -o table
```

### Validate full deployment
```bash
bash scripts/validate-deployment.sh \
    --resource-group rg-tktph-avd-prod-sea \
    --host-pool tktph-hp
```

---

## 📞 Support

| Role | Contact |
|------|---------|
| Platform Owner | tom.tuerlings@tktconsulting.com |
| Documentation | [AI-AGENT-CONTEXT.md](AI-AGENT-CONTEXT.md) |

---

## 📜 Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.0 | 2026-02-12 | Initial automated deployment |
| 5.0 | 2026-02-13 | Validation improvements, bug fixes |
| **6.2** | **2026-02-13** | **Entra ID join fix, VM RBAC, managed identity** |

---

*Built with ❤️ for TKT Consulting*
