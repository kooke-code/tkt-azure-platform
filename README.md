# TKT Azure Platform

Azure Virtual Desktop infrastructure for TKT Consulting Philippines SAP managed services.

## Active Version: V9.0

**Use `azure-platform/tkt-azure-platform-v9/`** for all new deployments.

V9.0 features:
- 6 named consultants with `users.json` configuration
- 3 session hosts (2 users/VM for browser-heavy SAP Fiori)
- Conditional Access: MFA + Philippines/Belgium location restriction
- Teams team with P2P, R2R, Client, Reports channels
- Break-glass admin with Azure Key Vault credential storage
- Optional ActivTrak productivity monitoring
- Azure AD Kerberos authentication (no shared keys)
- Azure Firewall with FQDN application rules

```bash
cd azure-platform/tkt-azure-platform-v9
cp scripts/users.json.template scripts/users.json  # Configure users
bash scripts/deploy-avd-platform.sh                 # Deploy platform
bash scripts/deploy-azure-firewall.sh --sku Basic   # Deploy firewall
bash scripts/deploy-conditional-access.sh            # Deploy CA policies
bash scripts/deploy-teams-team.sh                    # Create Teams team
```

See [V9 README](azure-platform/tkt-azure-platform-v9/README.md) for full documentation.

## Version History

| Version | Date | Status | Key Changes |
|---------|------|--------|-------------|
| **V9.0** | 2026-02-17 | **Active** | Named users, 6-person scale, CA, Teams, ActivTrak |
| V8.1 | 2026-02-17 | Superseded | Azure AD Kerberos + Azure Firewall |
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
├── tkt-azure-platform-v9/       # ACTIVE - deploy from here
│   ├── scripts/
│   │   ├── deploy-avd-platform.sh
│   │   ├── deploy-azure-firewall.sh
│   │   ├── deploy-conditional-access.sh
│   │   ├── deploy-teams-team.sh
│   │   ├── destroy-platform.sh
│   │   └── users.json.template
│   ├── knowledge-base/
│   ├── templates/
│   ├── docs/
│   ├── README.md
│   ├── CHANGELOG.md
│   └── AI-AGENT-CONTEXT.md
├── tkt-azure-platform-v8/       # Superseded by V9
├── tkt-azure-platform-v7/       # Archived (reference only)
├── tkt-azure-platform-v6.3/     # Archived
├── tkt-azure-platform-v6.2/     # Archived
├── tkt-azure-platform-v5/       # Archived
├── tkt-azure-platform-v4/       # Archived
└── tkt-azure-platform-v3/       # Archived
```
