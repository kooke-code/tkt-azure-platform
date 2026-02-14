# TKT Philippines AVD Platform - Changelog

## Version 7.0 (February 14, 2026)

### 🎯 Consolidation Release

V7 is a comprehensive consolidation of all files from V3 through V6.3 into a single, complete package. No files are lost between versions.

### 🔄 Restored Files (Previously Lost)

These files existed in earlier versions but were not carried forward:

| File | Source | Purpose |
|------|--------|---------|
| `docs/cost-optimization.md` | V3 | 85% cost reduction guide (€1,487 → €220/month) |
| `docs/governance-implementation.md` | V3 | RBAC, policies, compliance, GDPR framework |
| `docs/validation-checklist.md` | V3 | 24-test manual smoke test checklist |
| `scripts/Configure-VMHardening.ps1` | Root | USB blocking, RDP security, folder redirection |
| `scripts/optional/deploy-azure-firewall.sh` | Root | Optional Azure Firewall with URL filtering |
| `scripts/optional/setup-monitoring-alerts.sh` | Root | VM heartbeat, CPU, disk, login alerts |
| `scripts/optional/setup-azure-files.sh` | Root | Azure Files share setup |
| `scripts/terraform/main.tf` | Root | Infrastructure as Code option |
| `templates/philippines-customer-template.json` | Root | Customer configuration template |

### ✅ Structure Improvements

- **Flat structure**: Fixed V6.3 double-nested folder issue
- **macOS compatible**: All scripts use bash 3.2 (no bash 4+ features)
- **Optional scripts**: Enhanced security scripts moved to `scripts/optional/`
- **Complete docs**: 10 documentation files covering architecture to governance
- **All templates**: 6 templates including restored customer template

### 📊 V7 Complete Inventory

| Category | Count | Details |
|----------|-------|---------|
| Core scripts | 15 | Deploy, validate, configure, provision |
| Optional scripts | 3 | Firewall, monitoring, Azure Files |
| PowerShell scripts | 2 | VM hardening, Conditional Access |
| Terraform | 1 | IaC alternative |
| Documentation | 10 | Architecture to governance |
| Templates | 6 | Config, policies, provisioning |
| **Total** | **37** | Complete platform package |

### 🔧 Deploy Script

Based on `deploy-avd-platform-v6.3-fixed.sh` - includes all V6.2 + V6.3 critical fixes:
- Entra ID join with `targetisaadjoined:i:1`
- Stale device cleanup before VM creation
- Teams + WebRTC Redirector + M365 Apps installation
- Managed identity + AADLoginForWindows extension
- bash 3.2 compatible (no associative arrays)

---

## Version 6.3 (February 13, 2026)

### 🔴 Critical Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Session hosts stuck "Unavailable" | Host pool missing Entra ID join RDP property | Added `--custom-rdp-property "targetisaadjoined:i:1"` to host pool creation |
| Entra ID join fails with "hostname_duplicate" | Stale device records from previous deployments | Added cleanup step to delete existing Entra ID device records before VM creation |
| Teams not working properly in AVD | Missing WebRTC Redirector and registry settings | Added WebRTC Redirector installation + `IsWVDEnvironment=1` registry key |

### ✨ New Features

- **Phase 4.5: Application Installation** - Automated installation of:
  - Microsoft Teams (new Teams client for AVD)
  - Microsoft 365 Apps (Office) with shared computer licensing
  - WebRTC Redirector for Teams media optimization
  - Teams AVD environment registry configuration

- **Comprehensive Validation Script** - New `validate-deployment-comprehensive.sh`:
  - 50+ automated checks across all components
  - Auto-discovers resources (no hardcoded names)
  - Checks: Infrastructure, AVD Control Plane, Session Hosts, Applications, Identity, Entra Devices
  - Pass/Fail/Warning summary with percentage score

- **Shared File Share** - Optional shared drive for consultant collaboration

### 📋 Files Changed

| File | Change |
|------|--------|
| `scripts/deploy-avd-platform.sh` | Added V6.3 fixes + Phase 4.5 |
| `scripts/validate-deployment-comprehensive.sh` | **NEW** - Dynamic validation |
| `docs/known-issues.md` | Updated with resolved issues |
| `CHANGELOG.md` | **NEW** |

---

## Version 6.2 (February 13, 2026)

### Initial Entra ID Join Support
- Added managed identity to VMs (`--assign-identity`)
- Added AADLoginForWindows extension for cloud-only join
- Added Virtual Machine User Login RBAC role assignment
- Fixed aadJoin parameter in DSC extension
- Extended wait time for Entra ID join completion (90s + 15 retries)

### Scripts Added
- `fix-entra-id-join.sh` - Troubleshooting script for join issues
- `setup-session-logging.sh` - Session recording setup
- `setup-session-host-hardening.sh` - Security hardening
- `setup-fslogix-profiles.sh` - Profile management
- `setup-vm-schedule.sh` - Auto-shutdown configuration
- `setup-avd-alerts.sh` - Monitoring alerts
- `generate-deployment-report.sh` - Deployment documentation
- `provision-avd-users.sh` - Bulk user provisioning
- `setup-entra-id-automation.sh` - Entra ID automation
- `transfer-ownership.sh` - Ownership transfer helper

---

## Version 6.1 and Earlier

### V6.1
- Initial automation framework
- 6-phase deployment structure
- Basic validation

### V5.0
- Semi-automated deployment
- Manual Entra ID configuration required

### V4.0
- Complete redesign after V2 failure
- Cost optimization (85% reduction)
- Southeast Asia region deployment

### V2.0 (Failed)
- Windows Server approach
- Network connectivity issues
- Abandoned in favor of V4 redesign
