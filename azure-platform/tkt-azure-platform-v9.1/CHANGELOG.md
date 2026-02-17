# TKT Philippines AVD Platform - Changelog

## Version 9.1 (February 17, 2026)

### Role-Split Deployment (Track A / Track B)

V9.1 splits the monolithic `deploy-avd-platform.sh` into two independent deployment tracks,
enabling operators with different permission levels to deploy without sharing credentials:

- **Track A (Global Admin)**: Identity provisioning — users, groups, break-glass, Conditional Access, Teams
- **Track B (Contributor + User Access Administrator)**: Infrastructure — networking, storage, AVD, VMs, firewall, monitoring, RBAC, governance

### Why This Change

Yannick (`yannick.deridder@tktconsulting.be`) has **Contributor + User Access Administrator** on the Azure subscription but **no Entra ID directory roles**. The Global Admin is `config@tktconsulting.be`. The v9.0 monolithic script required Global Admin to run the entire deployment, even though most operations only needed Contributor.

### New Scripts

| Script | Track | Purpose |
|--------|-------|---------|
| `deploy-identity.sh` | A | Create security group, users (from users.json), break-glass admin, device cleanup |
| `deploy-infra.sh` | B | All infrastructure: networking, storage, AVD, VMs, applications, logging, RBAC, governance |
| `destroy-identity.sh` | A | Delete users, groups, CA policies, named locations, device records |
| `destroy-infra.sh` | B | Deallocate VMs, remove locks, delete firewall/KV/RG |

### Deployment Order

```
Track A (Global Admin):
  1. deploy-identity.sh
  2. deploy-conditional-access.sh
  3. deploy-teams-team.sh
  4. Assign M365 F3 licenses (manual)

Track B (Contributor):
  5. deploy-infra.sh        (validates Track A completed)
  6. deploy-azure-firewall.sh (optional)

Teardown (reverse):
  1. destroy-infra.sh       (Track B)
  2. destroy-identity.sh    (Track A)
```

### Track B Validation

`deploy-infra.sh` validates the security group exists before proceeding. If Track A has not been run, the script fails fast with a clear error message instead of failing halfway through infrastructure deployment.

### Script Details

**`deploy-identity.sh` (Track A)**:
- Loads user configuration from `users.json` (or uses defaults)
- Creates Entra ID security group
- Creates named users with display names, job titles, and group membership
- Creates break-glass admin with 32-char random password
- Optional stale device cleanup (`--skip-device-cleanup` to skip)
- Outputs credentials file and security group Object ID for Track B handoff

**`deploy-infra.sh` (Track B)**:
- Accepts `--security-group-name` parameter (default: `TKT-Philippines-AVD-Users`)
- Phase 1: Networking (RG, VNet, NSG, rules)
- Phase 2: Storage & Monitoring (storage account, FSLogix, Log Analytics)
- Phase 2.5: Shared Documentation Storage (shared-docs share + folders)
- Phase 3: AVD Control Plane (workspace, host pool, app group)
- Phase 4: Session Hosts (VMs, extensions, auto-shutdown)
- Phase 4.5: Applications (Teams, Edge, FSLogix, drive mapping, ActivTrak)
- Phase 4.6: Session Logging (DCR, audit policies, weekly export)
- Phase 5: RBAC & Key Vault (roles, Key Vault, break-glass credential storage)
- Phase 6: Security & Governance (locks, diagnostics, scaling, budget)
- Phase 7: Validation

### Updated Scripts

- `deploy-azure-firewall.sh`: Updated to v9.1, references changed from `deploy-avd-platform.sh` to `deploy-infra.sh`
- `deploy-conditional-access.sh`: Updated to v9.1, marked as Track A (Global Admin)
- `deploy-teams-team.sh`: Updated to v9.1, marked as Track A (Global Admin)

### New Documentation

- `docs/role-requirements.md`: Detailed role matrix per script (Azure RBAC + Entra ID roles)

### Removed

- `deploy-avd-platform.sh` (replaced by `deploy-identity.sh` + `deploy-infra.sh`)
- `destroy-platform.sh` (replaced by `destroy-identity.sh` + `destroy-infra.sh`)

### No Functional Changes

All Azure resources deployed are identical to V9.0. The split is purely organizational — same VMs, same storage, same networking, same security policies.

---

## Version 9.0 (February 17, 2026)

### Interactive Users, 6-Person Scale, Teams, Conditional Access

V9 scales the platform from 4 generic users to 6 named consultants, adds automated
Conditional Access policies, Teams team creation, optional ActivTrak monitoring,
and a break-glass admin with Key Vault credential storage.

### Architecture Changes

| Component | V8.1 | V9.0 |
|-----------|------|------|
| Users | 4 generic (`ph-consultant-001`) | 6 named (real names from `users.json`) |
| VMs | 2x Standard_D4s_v5 | 3x Standard_D4s_v5 (maintains 2 users/VM) |
| Teams | Client installed only | Team + 4 channels created via Graph API |
| Monitoring | Session logs + weekly export | + ActivTrak agent (optional) |
| Conditional Access | Manual (not scripted) | Automated: MFA + location + block legacy auth |
| Break-glass admin | None | Dedicated admin, excluded from CA, creds in Key Vault |
| License docs | None | M365 licensing guide for consultants |
| Credentials | Printed to console | Written to `credentials-TIMESTAMP.txt` |
| Estimated cost | ~EUR 280/month (platform) | ~EUR 390/month (platform) |

### New: User Configuration (`users.json`)

- Copy `scripts/users.json.template` to `scripts/users.json` and customize
- Each user has: username, display_name, role (P2P/R2R), job_title
- Deploy script reads JSON and creates users with real names
- VM count auto-calculated from user count (ceil(users/2))
- Fallback to interactive prompts if no JSON file provided

### New Script: `deploy-conditional-access.sh`

Automated Conditional Access via `az rest` + Microsoft Graph API:

- **Phase 1**: Named Locations — Philippines (PH) and Belgium (BE)
- **Phase 2**: Require MFA — All AVD users, exclude break-glass + Global Admins
- **Phase 3**: Location Restriction — Block access outside PH/BE
- **Phase 4**: Block Legacy Auth — Prevent Exchange ActiveSync and other legacy protocols
- **Phase 5**: Validation — List created policies and state
- **Modes**: `--report-only` (default, safe testing), `--enforce`, `--dry-run`

### New Script: `deploy-teams-team.sh`

Teams team and channels via Microsoft Graph API:

- Creates "TKT Philippines SAP Team"
- **4 custom channels**: P2P Knowledge Base, R2R Knowledge Base, Client Communications, Weekly Reports
- Adds all security group members as team members
- Disables Giphy, memes, and guest access
- Async team creation with polling for completion

### New: Break-Glass Admin

- Dedicated emergency admin account (`tktph-breakglass`)
- 32-character random password stored in Azure Key Vault
- Excluded from all Conditional Access policies
- Key Vault created automatically during platform deployment

### New: ActivTrak Integration (Optional)

- Set `ACTIVTRAK_ACCOUNT_ID` environment variable to enable
- Agent installed on all session hosts via `az vm run-command`
- Firewall rules for `*.activtrak.com` and `*.birchgrove.com` added automatically
- Skipped entirely if env var not set

### New: License Guide (`docs/license-guide.md`)

- Recommends M365 F3 (~EUR 3.70/user/month) for consultants
- Documents F3 vs Business Basic vs E3 trade-offs
- Windows 11 Enterprise multi-session licensing guidance

### Changes to `deploy-avd-platform.sh`

- Pre-flight: loads `users.json` (or prompts interactively) for named user creation
- Defaults: `USER_COUNT=6`, `VM_COUNT=3`, `VERSION_TAG="9.0"`
- Phase 4.5.6: ActivTrak agent installation (optional, gated by env var)
- Phase 5: Creates users with real names from JSON, break-glass admin with Key Vault
- Phase 5: Generates `credentials-TIMESTAMP.txt` (mode 600) with all user credentials
- Phase 5.5: Budget alert updated to EUR 450/month
- Summary: References new scripts (conditional access, teams, firewall)

### Changes to `deploy-azure-firewall.sh`

- Version bump to 9.0
- Optional ActivTrak firewall rules (`*.activtrak.com`, `*.birchgrove.com`)

### Changes to `destroy-platform.sh`

- Deletes Azure Key Vault (with purge protection handling)
- Deletes 3 Conditional Access policies + 2 named locations via Graph API
- Deletes break-glass admin user from Entra ID
- User count updated to 6

### Cost Impact

| Configuration | Monthly Cost |
|---------------|-------------|
| V9 platform (3 VMs) | ~EUR 390/month |
| V9 + Firewall Basic | ~EUR 670/month |
| V9 + Firewall Standard | ~EUR 1,290/month |
| Per consultant (6 users, with FW Basic) | ~EUR 112/month |

### Files

| Category | Count | Details |
|----------|-------|---------|
| Core scripts | 4 | Deploy platform, firewall, conditional access, teams |
| Teardown scripts | 1 | Destroy platform (incl. CA, KV, Teams cleanup) |
| Configuration | 1 | users.json.template |
| Documentation | 4 | README, CHANGELOG, AI-AGENT-CONTEXT, license-guide |
| Knowledge Base | 7+ | SOP templates, checklists, report templates |
| Templates | 1 | Weekly log export queries |
| **Total** | **18+** | Full managed services platform |

---

## Version 8.1 (February 17, 2026)

### Security: Azure AD Kerberos + Azure Firewall

V8.1 is a security-focused update that eliminates shared key authentication and adds
Layer 7 outbound filtering via Azure Firewall.

### Authentication: Azure AD Kerberos (replaces shared keys)

| Component | V8.0 | V8.1 |
|-----------|------|------|
| Storage auth | Storage account keys (cmdkey) | Azure AD Kerberos (identity-based) |
| FSLogix profiles | Key-based UNC access | Kerberos ticket via Entra ID |
| Shared-docs drive | cmdkey + storage key logon script | Kerberos SSO (no credentials) |
| Weekly log export | Storage key in wrapper script | Kerberos SSO via SYSTEM account |
| Folder creation | `--account-key` parameter | `--auth-mode login` (OAuth) |
| Shared key access | Enabled | **Disabled** after deployment |
| RBAC roles | SMB Share Contributor | + SMB Share Elevated Contributor |

### Changes to `deploy-avd-platform.sh`

- Phase 2: Storage account created with `--enable-files-aadkerb` + default share permission
- Phase 2.5: Folder creation uses OAuth (`--auth-mode login`) instead of account keys
- Phase 4.5.4: Cloud Kerberos Ticket Retrieval enabled on session hosts
- Phase 4.5.4: Shared-docs Z: drive mapped via Kerberos SSO (no cmdkey)
- Phase 4.5.5: FSLogix configured without storage key (Kerberos authentication)
- Phase 4.6: Weekly export wrapper no longer contains storage key
- Phase 5: Added `Storage File Data SMB Share Elevated Contributor` role
- Phase 5: Shared key access disabled on storage account after deployment
- All `storage_key` variable usage removed from script

### New Script: `deploy-azure-firewall.sh`

Separate deployment script for Azure Firewall with FQDN-based application rules:

- **8 phases**: Subnet, Firewall, App Rules, Network Rules, Routing, NSG, Diagnostics, Validation
- **Application rules** (FQDN Layer 7 filtering):
  - AVD service (`*.wvd.microsoft.com`, `*.servicebus.windows.net`)
  - Azure authentication (`login.microsoftonline.com`, `*.msauth.net`)
  - Azure Files (`*.file.core.windows.net`)
  - SAP Fiori (`*.s4hana.cloud.sap`, `*.sap.com`)
  - Zoho Desk (`*.zoho.com`, `*.zohocdn.com`)
  - Microsoft 365/Teams (`*.teams.microsoft.com`, `*.office365.com`)
  - Windows Update (`*.windowsupdate.com`, `kms.core.windows.net`)
- **Network rules** (non-HTTP protocols):
  - Teams TURN/STUN (UDP 3478-3481)
  - Teams media (TCP 50000-50059)
  - Azure Files SMB (TCP 445 -> Storage.SoutheastAsia)
  - DNS (UDP/TCP 53), NTP (UDP 123)
- **Route table**: 0.0.0.0/0 -> Azure Firewall private IP
- **SKU options**: Basic (~EUR 280/month) or Standard (~EUR 900/month)
- **Diagnostics**: Logs to existing Log Analytics workspace

### Cost Impact

| Configuration | Monthly Cost |
|---------------|-------------|
| V8 (no firewall) | ~EUR 280/month |
| V8.1 + Firewall Basic | ~EUR 560/month |
| V8.1 + Firewall Standard | ~EUR 1,180/month |

### Files

| Category | Count | Details |
|----------|-------|---------|
| Core scripts | 2 | Deploy platform + deploy firewall |
| Teardown scripts | 1 | Destroy platform |
| Documentation | 3 | README, CHANGELOG, AI-AGENT-CONTEXT |
| Knowledge Base | 7+ | SOP templates, checklists, report templates |
| Templates | 1 | Weekly log export queries |
| **Total** | **14+** | Security-hardened managed services package |

---

## Version 8.0 (February 14, 2026)

### Purpose: SAP Managed Services Platform

V8 transforms the AVD platform from a general-purpose deployment into a purpose-built
**SAP Managed Services workstation** for 4 consultants providing Procurement (P2P) and
Record-to-Report (R2R) services to a self-storage company on SAP S/4HANA Public Cloud.

### Architecture Changes

| Component | V7 | V8 |
|-----------|----|----|
| VM Size | Standard_D4s_v3 (4 vCPU, 16GB) | Standard_D4s_v5 (4 vCPU, 16GB) |
| Max Sessions per VM | 4 | 2 (browser-heavy workload) |
| SAP Access | SAP GUI (not installed) | Fiori via browser (HTTPS only) |
| Shared Storage | None | `shared-docs` share (50GB) with SOP structure |
| Session Logging | Basic (broken VM naming) | Full audit + weekly export pipeline |
| Teams | Basic install | Optimized: WebRTC + multimedia redirection |
| Knowledge Base | None | Structured SOP templates + weekly AI reports |
| Estimated Cost | ~EUR 235/month | ~EUR 280/month |

### Critical Bug Fixes from V7

| Bug | Impact | Fix |
|-----|--------|-----|
| `setup-session-logging.sh` uses 0-indexed VM names (`tktph-sh-0`) | Logging scripts target non-existent VMs | All scripts use 1-indexed with zero-padding: `vm-tktph-01` |
| FSLogix cleanup task references `fslogix-profiles` share | Cleanup fails silently | Corrected to `profiles` (matching actual share name) |
| `setup-vm-schedule.sh` weekday filtering parsed but never implemented | VMs start/stop on weekends too | Implemented proper `--week-days` in schedule creation |
| Storage keys printed to console in `setup-azure-files.sh` | Security: keys visible in terminal history | Removed all key printing; use `--auth-mode login` |
| Passwords visible in process listings | Security: `ps aux` shows passwords | Passwords read from stdin/file descriptors, not CLI args |
| `date -u -d "+1 day"` fails on macOS | Schedule creation fails | Cross-platform date handling (macOS + Linux) |

### New Features

#### Phase 2.5: Shared Documentation Storage
- Creates `shared-docs` Azure Files share (50GB) alongside FSLogix `profiles`
- Pre-creates folder structure:
  ```
  shared-docs/
    P2P/how-to/
    P2P/troubleshooting/
    P2P/configuration/
    R2R/how-to/
    R2R/troubleshooting/
    R2R/configuration/
    cross-functional/
    client-specific/
    weekly-reports/
  ```
- Mounted on all session hosts at `S:\` drive
- Accessible by all consultants for persistent documentation

#### Phase 4.5: Application Installation (Enhanced)
- **Browser optimization**: Edge pre-configured for Fiori and Zoho Desk workflows
- **Teams optimization**: WebRTC Redirector + multimedia redirection + AVD environment flag
- **No SAP GUI**: Client uses S/4HANA Public Cloud (Fiori only)
- Microsoft 365 Apps with shared computer licensing

#### Phase 4.6: Session Logging & Weekly Export
- Enhanced Windows audit policies (process creation, file access, logon/logoff)
- Azure Monitor Agent with Data Collection Rules
- Weekly scheduled task that exports past 7 days of session data to `shared-docs/weekly-reports/`
- Report includes: user sessions, applications launched, Fiori pages visited, Teams call duration, errors
- Reports designed for AI analysis to identify SOP gaps and improvement opportunities

#### Knowledge Base Templates
- Structured SOP templates for P2P (purchase orders, goods receipts, invoice verification)
- Structured SOP templates for R2R (journal entries, period-end close, reconciliation)
- Month-end close checklist (5-day schedule)
- Client system landscape template
- Weekly AI analysis report template

### Security Improvements
- All storage operations use `--auth-mode login` (no storage keys)
- Passwords read via secure methods (not CLI arguments)
- Registration tokens stored in memory, not temp files where possible
- NSG rules tailored for cloud SAP access (HTTPS outbound only)
- Resource tags on all resources for governance

### Files

| Category | Count | Details |
|----------|-------|---------|
| Core scripts | 1 | Consolidated deploy script (all phases) |
| Documentation | 3 | README, CHANGELOG, AI-AGENT-CONTEXT |
| Knowledge Base | 7+ | SOP templates, checklists, report templates |
| Templates | 2 | Customer config, weekly log export queries |
| **Total** | **13+** | Purpose-built managed services package |

---

## Previous Versions

See `tkt-azure-platform-v7/CHANGELOG.md` for V3-V7 history.
