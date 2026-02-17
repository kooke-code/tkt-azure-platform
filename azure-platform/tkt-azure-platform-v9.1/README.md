# TKT Philippines AVD Platform - V9.1

**SAP Managed Services Workstation for S/4HANA Public Cloud**

Azure Virtual Desktop environment purpose-built for 6 SAP consultants providing Procurement (P2P) and Record-to-Report (R2R) managed services to a self-storage company.

## V9.1: Role-Split Deployment

V9.1 splits the monolithic deploy script into two tracks, enabling operators with different permission levels to deploy independently:

```
┌─────────────────────────────────────────────┐
│  TRACK A — Global Admin (config@...)        │
│                                             │
│  1. deploy-identity.sh                      │
│  2. deploy-conditional-access.sh            │
│  3. deploy-teams-team.sh                    │
│  4. Assign M365 F3 licenses (manual)        │
│                                             │
│  ── hand off to Track B operator ──         │
│                                             │
│  TRACK B — Contributor (yannick@...)        │
│                                             │
│  5. deploy-infra.sh                         │
│  6. deploy-azure-firewall.sh (optional)     │
│                                             │
│  TEARDOWN (reverse order):                  │
│  1. destroy-infra.sh          (Track B)     │
│  2. destroy-identity.sh       (Track A)     │
└─────────────────────────────────────────────┘
```

## What This Deploys

| Component | Details |
|-----------|---------|
| **Session Hosts** | 3x Standard_D4s_v5 (4 vCPU, 16GB RAM) |
| **Max Users per VM** | 2 concurrent (browser-heavy workload) |
| **Total Users** | 6 consultants (named, from `users.json`) |
| **OS** | Windows 11 Enterprise Multi-Session |
| **Region** | Southeast Asia |
| **Identity** | Microsoft Entra ID Join (cloud-only) |
| **Authentication** | Azure AD Kerberos (no shared keys) |
| **Conditional Access** | MFA + Philippines/Belgium location restriction |
| **Applications** | Teams (optimized), Edge, Microsoft 365 Apps |
| **Teams Team** | Auto-created with P2P, R2R, Client, Reports channels |
| **Storage** | FSLogix profiles (100GB) + Shared docs (50GB) |
| **Firewall** | Azure Firewall with FQDN application rules |
| **Monitoring** | Session logging + weekly export + ActivTrak (optional) |
| **Break-Glass** | Admin account with credentials in Azure Key Vault |
| **Estimated Cost** | ~EUR 390/month (+ EUR 280/month with Firewall Basic) |

## Role Requirements

| Script | Azure RBAC | Entra ID Role |
|--------|-----------|---------------|
| `deploy-identity.sh` | — | Global Admin (or User Administrator) |
| `deploy-conditional-access.sh` | — | Conditional Access Admin (or Global Admin) |
| `deploy-teams-team.sh` | — | Teams Admin (or Global Admin) |
| `deploy-infra.sh` | Contributor + User Access Administrator | — |
| `deploy-azure-firewall.sh` | Contributor | — |
| `destroy-infra.sh` | Contributor + User Access Administrator | — |
| `destroy-identity.sh` | — | Global Admin (or User Administrator) |

See [docs/role-requirements.md](docs/role-requirements.md) for detailed role matrix.

## Prerequisites

- **Azure CLI v2.83+** (`az login` completed)
- **jq** (for JSON parsing in identity scripts)
- **Bash shell** (macOS, Linux, or Git Bash on Windows)

## Quick Start

### 1. Configure Users

```bash
git clone https://github.com/kooke-code/tkt-azure-platform.git
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v9.1

# Configure users (copy template and edit with real names)
cp scripts/users.json.template scripts/users.json
# Edit scripts/users.json with real consultant names
```

### 2. Track A — Identity (Global Admin)

```bash
# Create users, security group, break-glass admin
bash scripts/deploy-identity.sh

# Deploy Conditional Access policies (report-only first)
bash scripts/deploy-conditional-access.sh --report-only
# Test, then enforce:
# bash scripts/deploy-conditional-access.sh --enforce

# Create Teams team (optional)
bash scripts/deploy-teams-team.sh

# Assign M365 F3 licenses to all users (manual step — see docs/license-guide.md)
```

Note the **Security Group Object ID** from the output — Track B needs it to validate.

### 3. Track B — Infrastructure (Contributor)

```bash
# Set required variables
export ENTRA_DOMAIN="yourdomain.onmicrosoft.com"
export ALERT_EMAIL="you@example.com"

# Deploy infrastructure (validates Track A completed first)
bash scripts/deploy-infra.sh

# Deploy Azure Firewall (recommended for production)
bash scripts/deploy-azure-firewall.sh --sku Basic
```

`deploy-infra.sh` will validate that the security group from Track A exists before proceeding.

## Configuration

Override defaults via environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `ENTRA_DOMAIN` | `tktconsulting.be` | Entra ID domain |
| `ALERT_EMAIL` | `tom.tuerlings@tktconsulting.com` | Alert recipient |
| `VM_SIZE` | `Standard_D4s_v5` | Session host VM size |
| `VM_COUNT` | `3` | Number of session hosts |
| `MAX_SESSION_LIMIT` | `2` | Concurrent users per host |
| `ACTIVTRAK_ACCOUNT_ID` | (none) | ActivTrak account ID (optional) |
| `BREAK_GLASS_ENABLED` | `true` | Create break-glass admin |
| `LOCATION` | `southeastasia` | Azure region |
| `RESOURCE_GROUP` | `rg-tktph-avd-prod-sea` | Resource group name |
| `SECURITY_GROUP_NAME` | `TKT-Philippines-AVD-Users` | Entra ID security group |

## Shared Documentation Drive

All session hosts mount `S:\` with this structure:

```
S:\
├── P2P/
│   ├── how-to/           # Step-by-step procedures
│   ├── troubleshooting/  # Common errors and fixes
│   └── configuration/    # Client-specific P2P config
├── R2R/
│   ├── how-to/
│   ├── troubleshooting/
│   └── configuration/
├── cross-functional/     # Month-end close, master data
├── client-specific/      # System landscape, org structure
└── weekly-reports/       # Auto-generated session log exports
```

## Weekly Session Log Reports

Every Sunday at 23:00, each session host exports the past week's activity to
`S:\weekly-reports\YYYY-WNN-hostname-report.json`:

- User login/logout times and session duration
- Applications launched (with frequency)
- Fiori pages visited (SAP transaction activity)
- Teams call statistics
- Errors and warnings encountered

**Send these reports for AI analysis** to identify:
- Recurring issues that need new SOPs
- Process bottlenecks
- Training gaps
- Optimization opportunities

## Access

| Method | URL |
|--------|-----|
| **Web Client** | https://rdweb.wvd.microsoft.com/arm/webclient |
| **Windows App** | https://aka.ms/AVDWindowsApp |

Users: Named consultants from `users.json` (e.g., `ph-consultant-001@{ENTRA_DOMAIN}`)

## Cost Breakdown

| Resource | Monthly Cost |
|----------|-------------|
| 3x D4s_v5 VMs (business hours) | ~EUR 330 |
| FSLogix Premium Storage (100GB) | ~EUR 20 |
| Shared Docs Storage (50GB) | ~EUR 10 |
| Log Analytics (90 day retention) | ~EUR 15 |
| Key Vault (break-glass creds) | ~EUR 1 |
| Networking | ~EUR 15 |
| **Platform subtotal** | **~EUR 390/month** |
| Azure Firewall Basic (optional) | ~EUR 280/month |
| Azure Firewall Standard (optional) | ~EUR 900/month |
| **Total (with FW Basic)** | **~EUR 670/month** |
| **Per consultant (6 users)** | **~EUR 112/month** |

## Teardown

Teardown runs in **reverse order** (infrastructure first, identity second):

```bash
# Step 1: Track B operator destroys infrastructure
bash scripts/destroy-infra.sh

# Step 2: Track A operator destroys identity (after RG deletion completes)
bash scripts/destroy-identity.sh
```

## Files

```
tkt-azure-platform-v9.1/
├── scripts/
│   ├── deploy-identity.sh               # Track A: Users, groups, break-glass
│   ├── deploy-infra.sh                  # Track B: Networking, storage, AVD, VMs, RBAC
│   ├── deploy-azure-firewall.sh         # Track B: Azure Firewall with FQDN rules
│   ├── deploy-conditional-access.sh     # Track A: CA policies (MFA, location, legacy auth)
│   ├── deploy-teams-team.sh            # Track A: Teams team + channels via Graph API
│   ├── destroy-infra.sh                 # Track B: Infrastructure teardown
│   ├── destroy-identity.sh              # Track A: Identity teardown
│   └── users.json.template             # User configuration template
├── templates/
│   └── weekly-log-export-query.json    # KQL queries for weekly reports
├── knowledge-base/                      # SOP templates and knowledge articles
│   ├── P2P/
│   ├── R2R/
│   ├── cross-functional/
│   ├── client-specific/
│   └── weekly-reports/
├── docs/
│   ├── license-guide.md                # M365 licensing guidance
│   └── role-requirements.md            # Role matrix per script
├── README.md
├── CHANGELOG.md
└── AI-AGENT-CONTEXT.md
```

## Security (V9.1)

- **Azure AD Kerberos**: All Azure Files access (FSLogix profiles + shared-docs) authenticates
  via Entra ID Kerberos tickets. No storage account keys are used or stored anywhere.
  Shared key access is disabled on the storage account after deployment.
- **Azure Firewall**: FQDN-based outbound filtering restricts session hosts to only approved
  endpoints (SAP Fiori, Zoho Desk, Teams, Azure services, ActivTrak if enabled).
- **Conditional Access**: Three policies enforced via Microsoft Graph API:
  1. **Require MFA** for all AVD users (break-glass excluded)
  2. **Location restriction** to Philippines + Belgium only
  3. **Block legacy authentication** protocols
- **Break-Glass Admin**: Emergency admin account with 32-char password stored in Azure Key Vault.
  Excluded from all Conditional Access policies.
- **RBAC**: `Storage File Data SMB Share Contributor` + `Elevated Contributor` roles assigned
  to the AVD user group for identity-based file access.

## Differences from V9.0

See [CHANGELOG.md](CHANGELOG.md) for full details. Key change:
- **Role-split deployment**: Monolithic `deploy-avd-platform.sh` split into `deploy-identity.sh` (Track A) and `deploy-infra.sh` (Track B), enabling operators with different permission levels to deploy independently.
