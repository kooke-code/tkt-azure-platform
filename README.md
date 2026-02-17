# TKT Azure Platform

Azure Virtual Desktop infrastructure for TKT Consulting Philippines SAP managed services.

## Active Version: V8.1

**Use `azure-platform/tkt-azure-platform-v8/`** for all new deployments.

V8.1 features:
- Azure AD Kerberos authentication (no shared keys)
- Azure Firewall with FQDN application rules
- SAP Fiori + Zoho Desk optimized workstations
- Weekly session log exports for AI analysis
- Full SOP knowledge base structure

```bash
cd azure-platform/tkt-azure-platform-v8
bash scripts/deploy-avd-platform.sh          # Deploy platform
bash scripts/deploy-azure-firewall.sh        # Deploy firewall (recommended)
```

See [V8 README](azure-platform/tkt-azure-platform-v8/README.md) for full documentation.

## Version History

| Version | Date | Status | Key Changes |
|---------|------|--------|-------------|
| **V8.1** | 2026-02-17 | **Active** | Azure AD Kerberos + Azure Firewall |
| V8.0 | 2026-02-14 | Superseded | SAP managed services platform |
| V7 | 2026-02-14 | Archived | Consolidation release (v3-v6.3 unified) |
| V6.3 | Earlier | Archived | Teams, M365, Entra ID join fixes |
| V6.2 | Earlier | Archived | Monitoring added |
| V5 | Earlier | Archived | User provisioning |
| V4 | Earlier | Archived | Entra ID join |
| V3 | Earlier | Archived | Original AVD platform |

## Repository Structure

```
azure-platform/
├── tkt-azure-platform-v8/       # ACTIVE - deploy from here
│   ├── scripts/
│   │   ├── deploy-avd-platform.sh
│   │   ├── deploy-azure-firewall.sh
│   │   └── destroy-platform.sh
│   ├── knowledge-base/
│   ├── templates/
│   ├── README.md
│   ├── CHANGELOG.md
│   └── AI-AGENT-CONTEXT.md
├── tkt-azure-platform-v7/       # Archived (reference only)
├── tkt-azure-platform-v6.3/     # Archived
├── tkt-azure-platform-v6.2/     # Archived
├── tkt-azure-platform-v5/       # Archived
├── tkt-azure-platform-v4/       # Archived
└── tkt-azure-platform-v3/       # Archived
```
