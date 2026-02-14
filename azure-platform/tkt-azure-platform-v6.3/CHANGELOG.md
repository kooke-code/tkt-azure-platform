# TKT Philippines AVD Platform - Changelog

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
