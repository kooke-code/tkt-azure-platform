# TKT Philippines AVD Platform V7

Fully automated Azure Virtual Desktop deployment for SAP consultants

![version](https://img.shields.io/badge/version-7.0-blue)
![Azure](https://img.shields.io/badge/Azure-AVD-0078D4)
![cost](https://img.shields.io/badge/cost-€235%2Fmonth-green)
![join](https://img.shields.io/badge/join-Entra%20ID-orange)

---

## 🎯 About V7

V7 is a **consolidation release** that brings together all files from V3 through V6.3 into a single, complete package. Files that were lost between version upgrades have been restored, the broken double-nested V6.3 folder structure is fixed, and all scripts are macOS bash 3.2 compatible.

---

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/kooke-code/tkt-azure-platform.git
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v7

# Deploy (interactive prompts for passwords)
bash scripts/deploy-avd-platform.sh

# Validate deployment (comprehensive - auto-discovers resources)
bash scripts/validate-deployment-comprehensive.sh

# Or use basic validation with explicit parameters
bash scripts/validate-deployment.sh --resource-group rg-tktph-avd-prod-sea --host-pool tktph-hp
```

---

## 📋 Prerequisites

- Azure CLI v2.83+ (`az login` completed)
- Contributor role on Azure subscription
- User Administrator role in Entra ID
- Bash shell (macOS or Linux)
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
tkt-azure-platform-v7/
├── README.md                           # This file
├── AI-AGENT-CONTEXT.md                 # AI assistant context
├── CHANGELOG.md                        # Full version history (V3→V7)
├── docs/
│   ├── architecture.md                 # Detailed architecture
│   ├── architecture-notes.md           # Technical design decisions
│   ├── admin-runbook.md                # Day-to-day operations guide
│   ├── user-guide.md                   # End-user documentation
│   ├── known-issues.md                 # Known issues & resolutions
│   ├── migration-guide.md              # Upgrade guide
│   ├── TESTING.md                      # Testing procedures
│   ├── cost-optimization.md            # 🔄 RESTORED - 85% cost reduction guide
│   ├── governance-implementation.md    # 🔄 RESTORED - RBAC, policies, GDPR
│   └── validation-checklist.md         # 🔄 RESTORED - 24 manual smoke tests
├── scripts/
│   ├── deploy-avd-platform.sh          # Main deployment (all V6.3 fixes)
│   ├── validate-deployment-comprehensive.sh  # 50+ auto-discovery checks
│   ├── validate-deployment.sh          # Basic parametrized validation
│   ├── fix-entra-id-join.sh            # Entra ID join troubleshooting
│   ├── provision-avd-users.sh          # Bulk user provisioning
│   ├── setup-avd-alerts.sh             # AVD-specific monitoring alerts
│   ├── setup-entra-id-automation.sh    # Entra ID automation
│   ├── setup-fslogix-profiles.sh       # FSLogix profile containers
│   ├── setup-session-host-hardening.sh # Session host security
│   ├── setup-session-logging.sh        # Session recording/logging
│   ├── setup-vm-schedule.sh            # Auto start/stop scheduling
│   ├── generate-deployment-report.sh   # Deployment documentation
│   ├── transfer-ownership.sh           # Customer handover
│   ├── Setup-ConditionalAccess.ps1     # PowerShell CA policies
│   ├── Configure-VMHardening.ps1       # 🔄 RESTORED - VM hardening
│   ├── optional/
│   │   ├── deploy-azure-firewall.sh    # 🔄 RESTORED - Azure Firewall
│   │   ├── setup-monitoring-alerts.sh  # 🔄 RESTORED - Alert rules
│   │   └── setup-azure-files.sh        # 🔄 RESTORED - Azure Files
│   └── terraform/
│       └── main.tf                     # 🔄 RESTORED - IaC option
└── templates/
    ├── avd-config.json                 # AVD configuration
    ├── conditional-access.json         # CA policy templates
    ├── deployment-report-template.md   # Report template
    ├── graph-api-user-template.json    # Graph API user template
    ├── user-provisioning-intake.json   # User intake form
    └── philippines-customer-template.json  # 🔄 RESTORED - Customer template
```

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

### VM Hardening (Restored)
```powershell
# Apply VM hardening (USB blocking, RDP security, folder redirection)
.\scripts\Configure-VMHardening.ps1 -StorageAccount "stcustomer001ph" -Username "ph-lead-001"
```

### Deploy Conditional Access
```powershell
# PowerShell (report-only mode)
.\scripts\Setup-ConditionalAccess.ps1

# Enforce after testing
.\scripts\Setup-ConditionalAccess.ps1 -ReportOnlyMode $false
```

### Optional: Azure Firewall
```bash
# Deploy enhanced network security (adds ~€912/month)
bash scripts/optional/deploy-azure-firewall.sh
```

---

## 💰 Cost Breakdown

| Component | Monthly Cost |
|-----------|-------------|
| 2x D4s_v3 VMs (business hours only) | €190 |
| Premium FileStorage (100GB) | €20 |
| Log Analytics (~5GB) | €15 |
| Networking | €10 |
| **Total** | **€235** |

**85% reduction from V2** (€1,487 → €235). See `docs/cost-optimization.md` for details.

---

## 🛠️ Troubleshooting

### Session hosts "Unavailable"
```bash
bash scripts/fix-entra-id-join.sh rg-tktph-avd-prod-sea
```

### Full validation
```bash
bash scripts/validate-deployment-comprehensive.sh
```

### Manual smoke tests
See `docs/validation-checklist.md` for the 24-test manual checklist.

---

## 📜 Version History

| Version | Date | Changes |
|---------|------|---------|
| **7.0** | **2026-02-14** | **Consolidation: all files from V3-V6.3, restored lost content** |
| 6.3 | 2026-02-13 | Critical Entra ID fix, Teams/Office install, comprehensive validation |
| 6.2 | 2026-02-13 | Entra ID join support, managed identity, RBAC |
| 5.0 | 2026-02-13 | User provisioning, alert setup |
| 4.0 | 2026-02-12 | Initial automation framework |
| 3.0 | 2026-02-01 | Architecture redesign, cost optimization |
| 2.0 | 2026-01-30 | Failed Windows Server approach (abandoned) |

See `CHANGELOG.md` for full details.

---

## 📞 Support

| Role | Contact |
|------|---------|
| Platform Owner | tom.tuerlings@tktconsulting.com |
| Documentation | [AI-AGENT-CONTEXT.md](AI-AGENT-CONTEXT.md) |

---

*Built with ❤️ for TKT Consulting*
