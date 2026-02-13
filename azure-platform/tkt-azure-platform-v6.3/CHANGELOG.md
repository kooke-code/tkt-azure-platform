# TKT Philippines AVD Platform - Changelog

## Version 6.3 (February 13, 2026)

### 🔧 Critical Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Session hosts stuck "Unavailable" | Host pool missing Entra ID join RDP property | Added `--custom-rdp-property "targetisaadjoined:i:1"` to host pool creation |
| Entra ID join fails with "hostname_duplicate" | Stale device records from previous deployments | Added cleanup step to delete existing Entra ID device records before VM creation |
| Teams not working properly in AVD | Missing WebRTC Redirector and registry settings | Added WebRTC Redirector installation + `IsWVDEnvironment=1` registry key |

### ✨ New Features

- **Phase 4.5: Application Installation** - Automated installation of:
  - Microsoft Teams (new Teams client)
  - Microsoft 365 Apps (Office) with shared computer licensing
  - WebRTC Redirector for Teams media optimization
  - Teams AVD environment registry configuration

- **Shared Drive** - Optional shared file share (`S:` drive) for all consultants

- **Comprehensive Validation Script** - New `validate-deployment-comprehensive.sh` that checks:
  - Infrastructure (VNet, NSG, Storage, Log Analytics)
  - AVD Control Plane (Host Pool, Workspace, App Group, RDP properties)
  - Session Hosts (VM status, Entra ID join, health checks)
  - Applications (Teams, Office, WebRTC, FSLogix)
  - Identity (Users, Groups, RBAC roles)
  - Entra ID Devices

- **Dynamic Resource Discovery** - Validation script auto-discovers all resources instead of hardcoding names

### 📋 Planned for V6.4

- Folder redirection (Desktop/Documents → shared drive or OneDrive)
- Single Sign-On (SSO) configuration for Entra ID join
- Conditional Access policy templates
- URL filtering with Microsoft Defender
- Session recording to Azure Files

---

## Version 6.2 (February 13, 2026)

### Initial Entra ID Join Support
- Added managed identity to VMs
- Added AADLoginForWindows extension
- Added VM User Login RBAC role assignment
- Fixed session host registration issues

---

## Version 6.1 and Earlier

See previous documentation for V4-V6.1 changes.
