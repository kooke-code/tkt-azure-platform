# TKT Philippines AVD Platform - Changelog

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
