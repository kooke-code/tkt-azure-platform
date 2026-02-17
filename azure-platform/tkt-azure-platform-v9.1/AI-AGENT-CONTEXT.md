# AI Agent Context - TKT Philippines SAP Managed Services

This file provides context for AI assistants (Claude, etc.) when analyzing session logs,
helping consultants, or reviewing operations for this platform.

## Service Overview

**Provider**: TKT Consulting Philippines
**Client**: Self-storage company
**SAP System**: SAP S/4HANA Public Cloud
**Service Scope**: Procurement (P2P) and Record-to-Report (R2R) ticket resolution
**Ticket System**: Zoho Service Desk Cloud Plus (client's ITSM)
**Team Size**: 6 SAP consultants (3 P2P, 3 R2R)

## Platform Version: V9.1 (Role-Split Deployment)

V9.1 splits deployment into two tracks for role separation:

- **Track A (Global Admin)**: Identity provisioning — `deploy-identity.sh`, `deploy-conditional-access.sh`, `deploy-teams-team.sh`
- **Track B (Contributor)**: Infrastructure — `deploy-infra.sh`, `deploy-azure-firewall.sh`

Track A must complete before Track B can run. Teardown runs in reverse: `destroy-infra.sh` first, then `destroy-identity.sh`.

## What the Consultants Do

### Procurement (P2P) - 3 Consultants
- Create and manage Purchase Orders via Fiori app F0842/F1943
- Process Goods Receipts via Fiori app F3814
- Verify and post Supplier Invoices via Fiori app F0859
- Manage vendor master data
- Handle 3-way match exceptions (PO vs GR vs Invoice)
- Run GR/IR clearing at month-end
- Resolve procurement tickets from Zoho Service Desk

### Record to Report (R2R) - 3 Consultants
- Post Journal Entries via Fiori app F2548/F0717
- Manage period-end closing tasks via Fiori app F3736
- Run account reconciliations
- Generate financial statements via Fiori app F1603
- Process bank reconciliations
- Run depreciation and asset accounting tasks
- Resolve R2R tickets from Zoho Service Desk

## Technical Environment

### Azure Infrastructure
- **Resource Group**: rg-tktph-avd-prod-sea
- **Region**: Southeast Asia (Singapore)
- **VMs**: 3x Standard_D4s_v5 (4 vCPU, 16GB RAM each)
- **Max 2 concurrent users per VM** (browser-heavy workload)
- **OS**: Windows 11 Enterprise Multi-Session
- **Identity**: Microsoft Entra ID Join (cloud-only)

### Applications on Session Hosts
- Microsoft Edge (primary browser for Fiori + Zoho Desk)
- Microsoft Teams (optimized for AVD with WebRTC redirector)
- Microsoft 365 Apps (Excel critical for reconciliations)
- No SAP GUI installed (S/4HANA Public Cloud = Fiori only)

### Storage (Kerberos Authentication)
- **FSLogix profiles**: `\\sttktphfslogix.file.core.windows.net\profiles` (100GB)
- **Shared docs**: `\\sttktphfslogix.file.core.windows.net\shared-docs` (50GB, mounted as Z:\)
- **Authentication**: Azure AD Kerberos (identity-based). No storage account keys used.
- **RBAC**: Users have `Storage File Data SMB Share Contributor` role (read/write/delete via Entra ID)
- **Shared key access**: Disabled on storage account. Only Kerberos/RBAC authentication works.

### Network (Azure Firewall)
- All SAP access is HTTPS to S/4HANA Public Cloud endpoints
- Zoho Desk access is HTTPS
- No VPN/ExpressRoute needed (all cloud services)
- **Azure Firewall** provides FQDN-based outbound filtering (Layer 7):
  - AVD service traffic (`*.wvd.microsoft.com`)
  - Azure authentication (`login.microsoftonline.com`)
  - Azure Files (`*.file.core.windows.net`)
  - SAP Fiori (`*.s4hana.cloud.sap`)
  - Zoho Desk (`*.zoho.com`)
  - Microsoft 365/Teams (`*.teams.microsoft.com`, `*.office365.com`)
  - ActivTrak (`*.activtrak.com`, `*.birchgrove.com`) — if enabled
  - All other outbound traffic is **denied**
- NSG provides additional Layer 3/4 defense-in-depth
- Route table forces all outbound traffic through Azure Firewall

### Security (V9.1)
- **Conditional Access**: 3 automated policies via Microsoft Graph:
  1. Require MFA for all AVD users (break-glass excluded)
  2. Location restriction to Philippines + Belgium only
  3. Block legacy authentication protocols
- **Break-Glass Admin**: Emergency admin (`tktph-breakglass`) with 32-char password in Azure Key Vault
- **ActivTrak** (optional): Productivity monitoring agent on session hosts, gated by `ACTIVTRAK_ACCOUNT_ID`

### Teams
- **Team**: "TKT Philippines SAP Team" auto-created via Graph API
- **Channels**: General, P2P Knowledge Base, R2R Knowledge Base, Client Communications, Weekly Reports
- All consultants added as members

## Deployment Scripts (V9.1)

| Script | Track | Role Required | Purpose |
|--------|-------|---------------|---------|
| `deploy-identity.sh` | A | Global Admin | Users, groups, break-glass |
| `deploy-conditional-access.sh` | A | CA Admin / Global Admin | MFA, location, legacy auth policies |
| `deploy-teams-team.sh` | A | Teams Admin / Global Admin | Teams team + channels |
| `deploy-infra.sh` | B | Contributor + UAA | Networking, storage, AVD, VMs, RBAC |
| `deploy-azure-firewall.sh` | B | Contributor | FQDN-based firewall rules |
| `destroy-infra.sh` | B | Contributor + UAA | Infrastructure teardown |
| `destroy-identity.sh` | A | Global Admin | Identity teardown |

## When Analyzing Session Logs

### What to Look For
1. **Session patterns**: Who's logging in when? Are business hours covered?
2. **Application usage**: What Fiori apps are being used most? Any unexpected apps?
3. **Error patterns**: Recurring errors suggest SOP gaps or training needs
4. **Productivity signals**: Time between actions, idle time, task completion patterns
5. **Security events**: Failed logins, after-hours access, unusual data exports

### Key Fiori Apps to Track

| App ID | Name | Module | Expected Usage |
|--------|------|--------|---------------|
| F0842 | Create Purchase Order | P2P | Daily, high volume |
| F1943 | Manage Purchase Orders | P2P | Daily |
| F3814 | Post Goods Receipt | P2P | Daily |
| F0859 | Create Supplier Invoice | P2P | Daily |
| F2548 | Manage Journal Entries | R2R | Daily |
| F3736 | Manage Closing Tasks | R2R | Month-end heavy |
| F1603 | Display Financial Statement | R2R | Weekly/month-end |
| F0401 | Approve Purchase Orders | P2P | As needed |

### Red Flags in Logs
- Access to Fiori admin apps (user management, config) by consultants
- Bulk data exports (large Excel downloads from ALV grids)
- After-hours access during non-month-end periods
- Repeated failed login attempts
- Access from unexpected IP addresses
- Long idle sessions (may indicate forgotten logoff)

## When Helping Consultants

### Approach
1. Always reference the SOPs in `S:\` (or `knowledge-base/` in this repo)
2. For P2P questions, check `S:\P2P\how-to\` for existing procedures
3. For R2R questions, check `S:\R2R\how-to\` for existing procedures
4. If no SOP exists, help create one following the template format
5. For month-end questions, reference `S:\cross-functional\month-end-close-checklist.md`

### Common Scenarios
- "The 3-way match is failing" -> Check tolerances, GR quantities, PO pricing
- "Journal entry won't post" -> Check posting period open, account assignments, authorizations
- "Month-end close is blocked" -> Check prerequisite tasks in close checklist
- "Vendor invoice is blocked for payment" -> Check GR/IR match, approval workflow

## Segregation of Duties

With 6 consultants, SoD is managed by splitting P2P and R2R with additional coverage:

| Role | Can Do | Cannot Do |
|------|--------|-----------|
| P2P Consultant 1 | Vendor master, PO creation | Goods receipt, invoice posting |
| P2P Consultant 2 | Goods receipt, invoice verification | Vendor master, PO creation |
| P2P Consultant 3 | PO approval, exception handling | Vendor master changes |
| R2R Consultant 4 | Journal entries, reconciliations | Period close execution |
| R2R Consultant 5 | Period close, asset accounting | Journal entry creation |
| R2R Consultant 6 | Financial reporting, bank reconciliation | Journal entry creation |

Cross-coverage: P2P consultants back up R2R (never within same P2P role), and vice versa.

## Weekly Report Analysis Framework

When reviewing the weekly log export (`S:\weekly-reports\`), produce a report covering:

1. **Operations Summary**: Sessions, hours worked, tickets likely handled
2. **SAP Activity**: Which Fiori apps used, transaction volumes, any unusual patterns
3. **Issues Identified**: Errors, failed actions, potential SOP gaps
4. **Recommendations**: New SOPs needed, process improvements, training suggestions
5. **Trend Analysis**: Compare with previous weeks for patterns
