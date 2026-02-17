# TKT Philippines AVD Platform - V9.0

**SAP Managed Services Workstation for S/4HANA Public Cloud**

Azure Virtual Desktop environment purpose-built for 6 SAP consultants providing Procurement (P2P) and Record-to-Report (R2R) managed services to a self-storage company.

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

## How Consultants Work

```
Consultant (laptop/thin client)
    |
    v  RDP via AVD Gateway (port 443)
Azure Virtual Desktop Session Host
    |
    ├── Edge Browser → SAP S/4HANA Public Cloud (Fiori)
    ├── Edge Browser → Zoho Service Desk Cloud Plus
    ├── Microsoft Teams → Client calls, internal comms
    ├── Microsoft 365 → Excel (reconciliations), Outlook
    └── S:\ Drive → Shared SOPs, knowledge base, weekly reports
```

## Prerequisites

- **Azure CLI v2.83+** (`az login` completed)
- **Contributor role** on Azure subscription
- **User Administrator role** in Entra ID
- **Bash shell** (macOS or Linux)

## Quick Start

```bash
git clone https://github.com/kooke-code/tkt-azure-platform.git
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v9

# Set your domain (required)
export ENTRA_DOMAIN="yourdomain.onmicrosoft.com"
export ALERT_EMAIL="you@example.com"

# Configure users (copy template and edit with real names)
cp scripts/users.json.template scripts/users.json
# Edit scripts/users.json with real consultant names

# Deploy platform (3 VMs, 6 users, break-glass admin)
bash scripts/deploy-avd-platform.sh

# Deploy Azure Firewall (recommended for production)
bash scripts/deploy-azure-firewall.sh --sku Basic

# Deploy Conditional Access (recommended)
bash scripts/deploy-conditional-access.sh --report-only
# Test, then enforce: bash scripts/deploy-conditional-access.sh --enforce

# Create Teams team (optional)
bash scripts/deploy-teams-team.sh
```

The deploy script will prompt for:
1. Azure subscription selection
2. Domain confirmation
3. Admin password (12+ chars)
4. Temporary user password
5. Alert email confirmation
6. VM size selection

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

## Files

```
tkt-azure-platform-v9/
├── scripts/
│   ├── deploy-avd-platform.sh         # Main deployment (all phases, Kerberos auth)
│   ├── deploy-azure-firewall.sh       # Azure Firewall with FQDN rules
│   ├── deploy-conditional-access.sh   # Conditional Access policies (MFA, location, legacy auth)
│   ├── deploy-teams-team.sh           # Teams team + channels via Graph API
│   ├── destroy-platform.sh            # Teardown (all resources incl. CA, KV, Teams)
│   └── users.json.template            # User configuration template (copy to users.json)
├── templates/
│   └── weekly-log-export-query.json   # KQL queries for weekly reports
├── knowledge-base/                    # SOP templates and knowledge articles
│   ├── P2P/
│   ├── R2R/
│   ├── cross-functional/
│   ├── client-specific/
│   └── weekly-reports/
├── docs/
│   └── license-guide.md              # M365 licensing guidance for consultants
├── README.md
├── CHANGELOG.md
└── AI-AGENT-CONTEXT.md
```

## Security (V9.0)

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

## Differences from V8.1

See [CHANGELOG.md](CHANGELOG.md) for full details. Key changes:
- **Named users**: 6 consultants with real names from `users.json` (replaces generic `ph-consultant-NNN`)
- **3 VMs**: Scaled from 2 to 3 session hosts (maintains 2 users/VM ratio)
- **Conditional Access**: Automated MFA + location restriction + legacy auth blocking
- **Teams team**: Auto-created with P2P, R2R, Client, Reports channels via Graph API
- **Break-glass admin**: Emergency account with Key Vault credential storage
- **ActivTrak**: Optional productivity monitoring agent on session hosts
- **License guide**: M365 licensing documentation for consultants
- **Credentials file**: All user credentials written to timestamped file (not just console)
