# TKT Philippines AVD Platform - V8

**SAP Managed Services Workstation for S/4HANA Public Cloud**

Azure Virtual Desktop environment purpose-built for 4 SAP consultants providing Procurement (P2P) and Record-to-Report (R2R) managed services to a self-storage company.

## What This Deploys

| Component | Details |
|-----------|---------|
| **Session Hosts** | 2x Standard_D4s_v5 (4 vCPU, 16GB RAM) |
| **Max Users per VM** | 2 concurrent (browser-heavy workload) |
| **OS** | Windows 11 Enterprise Multi-Session |
| **Region** | Southeast Asia |
| **Identity** | Microsoft Entra ID Join (cloud-only) |
| **Applications** | Teams (optimized), Edge, Microsoft 365 Apps |
| **Storage** | FSLogix profiles (100GB) + Shared docs (50GB) |
| **Monitoring** | Full session logging + weekly export |
| **Estimated Cost** | ~EUR 280/month |

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
cd tkt-azure-platform/azure-platform/tkt-azure-platform-v8

# Set your domain (required)
export ENTRA_DOMAIN="yourdomain.onmicrosoft.com"
export ALERT_EMAIL="you@example.com"

# Deploy
bash scripts/deploy-avd-platform.sh
```

The script will prompt for:
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
| `VM_COUNT` | `2` | Number of session hosts |
| `MAX_SESSION_LIMIT` | `2` | Concurrent users per host |
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

Users: `ph-consultant-001` through `ph-consultant-004@{ENTRA_DOMAIN}`

## Cost Breakdown

| Resource | Monthly Cost |
|----------|-------------|
| 2x D4s_v5 VMs (business hours) | ~EUR 220 |
| FSLogix Premium Storage (100GB) | ~EUR 20 |
| Shared Docs Storage (50GB) | ~EUR 10 |
| Log Analytics (90 day retention) | ~EUR 15 |
| Networking | ~EUR 15 |
| **Total** | **~EUR 280/month** |

## Files

```
tkt-azure-platform-v8/
├── scripts/
│   └── deploy-avd-platform.sh       # Main deployment (all phases)
├── templates/
│   └── weekly-log-export-query.json  # KQL queries for weekly reports
├── knowledge-base/                   # SOP templates and knowledge articles
│   ├── P2P/
│   ├── R2R/
│   ├── cross-functional/
│   ├── client-specific/
│   └── weekly-reports/
├── docs/                             # Platform documentation
├── README.md
├── CHANGELOG.md
└── AI-AGENT-CONTEXT.md
```

## Differences from V7

See [CHANGELOG.md](CHANGELOG.md) for full details. Key changes:
- VM sizing for browser-heavy SAP Fiori workloads (2 users/VM, not 4)
- Shared documentation drive for SOPs and knowledge capture
- Weekly session log exports for AI-powered operations analysis
- Teams call optimization (WebRTC + multimedia redirection)
- All critical V7 bugs fixed (VM naming, FSLogix share name, scheduling)
