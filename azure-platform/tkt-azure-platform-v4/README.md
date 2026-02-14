# TKT Philippines AVD Platform V4

**Fully automated Azure Virtual Desktop deployment for SAP consultants**

[![Version](https://img.shields.io/badge/version-4.0-blue.svg)]()
[![Azure](https://img.shields.io/badge/Azure-AVD-0078D4.svg)]()
[![Cost](https://img.shields.io/badge/cost-€220%2Fmonth-green.svg)]()

---

## 🚀 Quick Start

```bash
# 1. Clone and enter directory
cd tkt-azure-platform-v4/scripts

# 2. Make scripts executable
chmod +x *.sh

# 3. Login to Azure
az login

# 4. Run deployment (dry-run first)
./deploy-avd-platform-v4.sh --dry-run

# 5. Run actual deployment
./deploy-avd-platform-v4.sh
```

**Time:** ~45 minutes | **Cost:** ~€220/month | **Users:** 4 consultants

---

## 📋 Prerequisites

| Requirement | Version/Details |
|-------------|-----------------|
| Azure CLI | v2.50+ |
| Azure Subscription | Contributor role |
| Entra ID | Global Administrator |
| M365 Licenses | 4x Business Premium |

---

## 📦 What Gets Deployed

```
┌─────────────────────────────────────────────────────────┐
│  AVD Platform (Southeast Asia)                          │
├─────────────────────────────────────────────────────────┤
│  • 2 Session Hosts (D4s_v5, Windows 11 AVD)            │
│  • Pooled Host Pool (4 max sessions)                    │
│  • Premium FileStorage (100GB FSLogix profiles)         │
│  • Log Analytics (90-day retention)                     │
│  • 4 Entra ID users with M365 BP licenses               │
│  • Conditional Access (MFA required)                    │
│  • VM Schedule: 07:00-18:00 Brussels time (optional)    │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
tkt-azure-platform-v4/
├── scripts/
│   ├── deploy-avd-platform-v4.sh      # Main orchestrator (6 phases)
│   ├── setup-session-host-hardening.sh # Security hardening
│   ├── setup-entra-id-automation.sh   # Users, licenses, MFA
│   ├── setup-fslogix-profiles.sh      # Profile containers
│   ├── setup-vm-schedule.sh           # Auto start/stop schedule
│   ├── setup-session-logging.sh       # Activity logging
│   ├── validate-deployment.sh         # Health checks
│   └── generate-deployment-report.sh  # Reporting
├── docs/
│   ├── v4-architecture-notes.md
│   ├── v4-known-issues.md
│   ├── v4-migration-guide.md
│   └── TESTING.md
├── templates/
│   ├── graph-api-user-template.json
│   ├── conditional-access-policy.json
│   └── deployment-report-template.md
├── AI-AGENT-CONTEXT.md                # Prompt context for AI assistants
└── README.md
```

---

## 🎯 Deployment Phases

| Phase | Description | Time |
|-------|-------------|------|
| 1 | Networking (VNet, NSG) | 2 min |
| 2 | Storage & Monitoring | 5 min |
| 3 | AVD Control Plane | 3 min |
| 4 | Session Hosts (2 VMs) | 20 min |
| 5 | Identity (Users, MFA) | 5 min |
| 6 | Validation & Report | 5 min |

---

## ✅ After Deployment

1. **Enable MFA Policy**: Entra ID → Conditional Access → Enable "TKT-AVD-Require-MFA"
2. **Distribute Credentials**: Share user passwords via secure channel
3. **Install SAP GUI**: RDP to session hosts and install applications
4. **Test Login**: https://rdweb.wvd.microsoft.com/arm/webclient

---

## 🔧 Scripts Reference

### Core Deployment
| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-avd-platform-v4.sh` | Full deployment | `./deploy-avd-platform-v4.sh [--dry-run]` |
| `validate-deployment.sh` | Health checks | `./validate-deployment.sh --resource-group <rg> --host-pool <hp>` |
| `generate-deployment-report.sh` | Create report | `./generate-deployment-report.sh --resource-group <rg>` |

### Optional Features (run after deployment)
| Script | Purpose | Usage |
|--------|---------|-------|
| `setup-vm-schedule.sh` | Auto start 07:00 / stop 18:00 Brussels | `./setup-vm-schedule.sh --resource-group <rg> --vm-prefix <pfx> --vm-count 2` |
| `setup-session-logging.sh` | Activity logging + optional video | `./setup-session-logging.sh --resource-group <rg>` |

---

## 💰 Cost Breakdown

| Component | Monthly Cost |
|-----------|--------------|
| 2x D4s_v5 VMs | €190 |
| Premium Storage | €20 |
| Log Analytics | €5 |
| Networking | €5 |
| **Total** | **€220** |

*85% savings vs V2 architecture (€1,487)*

---

## 📚 Documentation

- [Architecture Notes](docs/v4-architecture-notes.md)
- [Known Issues](docs/v4-known-issues.md)
- [Migration Guide](docs/v4-migration-guide.md)
- [Testing Guide](docs/TESTING.md)

---

## 🆘 Support

- **Logs:** `/tmp/avd-deployment-*.log`
- **Validation:** `./validate-deployment.sh --output json`
- **Issues:** Check [v4-known-issues.md](docs/v4-known-issues.md)

---

**Version 4.0** | TKT Consulting | 2026
