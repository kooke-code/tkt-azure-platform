# TKT Philippines AVD Platform v6.3

Enterprise-grade Azure Virtual Desktop infrastructure for SAP consultants in the Philippines.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/kooke-code/tkt-azure-platform.git
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v6.3

# Login to Azure
az login

# Run deployment
chmod +x scripts/deploy-avd-platform.sh
./scripts/deploy-avd-platform.sh

# Validate deployment
chmod +x scripts/validate-deployment-comprehensive.sh
./scripts/validate-deployment-comprehensive.sh --resource-group rg-tktph-avd-prod-sea
```

## 📦 What's Included

### Scripts
| Script | Purpose |
|--------|---------|
| `deploy-avd-platform.sh` | Main deployment script (all phases) |
| `validate-deployment-comprehensive.sh` | Comprehensive validation (50+ checks) |

### Key Features (V6.3)
- ✅ **Entra ID Join** - Cloud-only identity, no AD DS required
- ✅ **Teams Optimization** - WebRTC Redirector + AVD environment config
- ✅ **Microsoft 365 Apps** - Automated Office installation with shared licensing
- ✅ **Stale Device Cleanup** - Prevents "hostname_duplicate" errors
- ✅ **Comprehensive Validation** - 50+ automated checks
- ✅ **Dynamic Discovery** - No hardcoded resource names

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure (Southeast Asia)                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Resource Group: rg-tktph-avd-prod-sea      │ │
│  │  ┌───────────────────────────────────────────────────┐  │ │
│  │  │  VNet: 10.2.0.0/16                                │  │ │
│  │  │  ┌─────────────────────────────────────────────┐  │  │ │
│  │  │  │  Subnet: snet-avd (10.2.1.0/24)             │  │  │ │
│  │  │  │  ┌─────────┐ ┌─────────┐                    │  │  │ │
│  │  │  │  │vm-tktph │ │vm-tktph │  Session Hosts     │  │  │ │
│  │  │  │  │   -01   │ │   -02   │  (Entra ID Join)   │  │  │ │
│  │  │  │  └────┬────┘ └────┬────┘                    │  │  │ │
│  │  │  │       └─────┬─────┘                         │  │  │ │
│  │  │  └─────────────┼───────────────────────────────┘  │  │ │
│  │  └────────────────┼──────────────────────────────────┘  │ │
│  │                   │                                      │ │
│  │  ┌────────────────▼──────────────────┐                  │ │
│  │  │  AVD Control Plane                │                  │ │
│  │  │  • Host Pool (targetisaadjoined)  │                  │ │
│  │  │  • Workspace                      │                  │ │
│  │  │  • Application Group              │                  │ │
│  │  └───────────────────────────────────┘                  │ │
│  │                                                          │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐        │ │
│  │  │Azure Files  │ │Log Analytics│ │Action Group │        │ │
│  │  │• profiles   │ │(90 days)    │ │(Alerts)     │        │ │
│  │  │• shared     │ │             │ │             │        │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘        │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 💰 Estimated Costs

| Component | Monthly Cost |
|-----------|-------------|
| 2x D4s_v4 VMs (8 vCPU, 32GB each) | ~€180 |
| Premium FileStorage (100GB profiles + 50GB shared) | ~€25 |
| Log Analytics (90-day retention) | ~€15 |
| Networking (VNet, NSG) | ~€5 |
| **Total** | **~€225/month** |

*Auto-shutdown can reduce VM costs by 50%+ during off-hours*

## 🔒 Security Features

- **Entra ID Join** - No traditional AD, cloud-only identity
- **NSG** - Network security group on subnet
- **No Public IPs** - VMs only accessible via AVD
- **MFA Ready** - Works with Entra ID Conditional Access
- **RBAC** - Least privilege access model

## 📋 Prerequisites

- Azure CLI 2.50+ (`az --version`)
- Azure subscription with Contributor + User Access Administrator
- Available VM quota for D4s_v4 in Southeast Asia
- Entra ID tenant with user creation permissions

## 🧪 Validation

The comprehensive validation script checks:

| Category | Checks |
|----------|--------|
| Infrastructure | Resource group, VNet, Subnet, NSG, Storage, Log Analytics |
| AVD Control Plane | Host pool, Workspace, App group, RDP properties |
| Session Hosts | VM status, Identity, Health checks, Extensions |
| Applications | Teams, WebRTC, Office, FSLogix, Entra ID join |
| Identity | Users, Security group, RBAC roles |
| Entra Devices | Device registration in Entra ID |

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## 📄 License

Proprietary - TKT Consulting

## 🤝 Support

Contact: yannick.de.ridder@outlook.com
