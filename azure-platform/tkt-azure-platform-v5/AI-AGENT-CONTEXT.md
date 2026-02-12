# TKT Philippines AVD Platform V4 - AI Agent Context

**Use this prompt when working with an AI assistant on this deployment.**

---

## Project Overview

You are helping deploy and manage an **Azure Virtual Desktop (AVD) platform** for TKT Consulting's Philippines-based SAP consultants. The platform provides secure remote desktops for accessing customer SAP systems.

**Key facts:**
- **Users:** 4 SAP consultants in the Philippines
- **Region:** Azure Southeast Asia
- **Cost target:** ~€220/month
- **Security:** Enterprise-grade (MFA, session logging, no local storage)
- **Schedule:** VMs run 07:00-18:00 Brussels time, Mon-Fri

---

## Script Reference

### Core Deployment Scripts (Run in order for new deployment)

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `deploy-avd-platform-v4.sh` | **Main orchestrator** - deploys entire platform in 6 phases | Fresh deployment |
| `validate-deployment.sh` | Health checks - runs 20+ tests | After deployment or troubleshooting |
| `generate-deployment-report.sh` | Creates deployment documentation | After deployment |

### Configuration Scripts (Run standalone as needed)

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `setup-session-host-hardening.sh` | Security: USB blocking, RDP restrictions, Defender | After VMs created (included in main deploy) |
| `setup-entra-id-automation.sh` | Creates users, assigns M365 licenses, configures MFA | After VMs created (included in main deploy) |
| `setup-fslogix-profiles.sh` | Configures FSLogix profile containers | After storage created (included in main deploy) |

### Optional Feature Scripts (Run on request)

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `setup-vm-schedule.sh` | **Auto start 07:00 / stop 18:00 Brussels time** | After deployment, on request |
| `setup-session-logging.sh` | **Activity logging + optional Teramind video recording** | After deployment, on request |

---

## Common Tasks

### Task: Fresh Deployment
```bash
cd scripts
chmod +x *.sh
./deploy-avd-platform-v4.sh --dry-run  # Preview first
./deploy-avd-platform-v4.sh            # Deploy
```

### Task: Enable Auto Start/Stop Schedule
```bash
./setup-vm-schedule.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2
```
**Result:** VMs start at 07:00 Brussels, stop at 18:00 Brussels, Mon-Fri only.

### Task: Enable Session Activity Logging
```bash
./setup-session-logging.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2
```
**Result:** All user activity (logins, apps launched, files accessed) logged to Log Analytics.

### Task: Enable Video Session Recording (Teramind)
**Prerequisites:** 
1. Create Teramind account at teramind.co (~€25/user/month)
2. Get deployment key from Teramind admin portal

```bash
./setup-session-logging.sh \
    --resource-group rg-tktph-avd \
    --vm-prefix tktph-sh \
    --vm-count 2 \
    --enable-teramind \
    --teramind-key "YOUR_DEPLOYMENT_KEY"
```
**Result:** Full video recording of all sessions, viewable in Teramind portal.

### Task: Validate Deployment Health
```bash
./validate-deployment.sh \
    --resource-group rg-tktph-avd \
    --host-pool tktph-hp \
    --output json
```

### Task: Generate Deployment Report
```bash
./generate-deployment-report.sh \
    --resource-group rg-tktph-avd \
    --output-dir ./reports
```

---

## Architecture Quick Reference

```
┌─────────────────────────────────────────────────────────────┐
│  AVD Platform (Southeast Asia) - €220/month                │
├─────────────────────────────────────────────────────────────┤
│  Session Hosts (2x D4s_v5)                                  │
│    • Windows 11 Enterprise AVD                              │
│    • 4 vCPU, 16GB RAM each                                  │
│    • FSLogix profiles on Azure Files                        │
│    • Auto-shutdown 18:00 Brussels (optional)                │
│                                                             │
│  Storage                                                    │
│    • Premium FileStorage 100GB                              │
│    • FSLogix profile containers                             │
│                                                             │
│  Security                                                   │
│    • Entra ID + MFA (Conditional Access)                    │
│    • USB blocked, clipboard restricted                      │
│    • Session activity logged to Log Analytics               │
│    • No local data storage (FSLogix redirect)               │
│                                                             │
│  Schedule (optional)                                        │
│    • Start: 07:00 Brussels time, Mon-Fri                    │
│    • Stop: 18:00 Brussels time, Mon-Fri                     │
│    • Weekends: VMs remain off                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Default Values

| Parameter | Default Value |
|-----------|---------------|
| Resource Group | `rg-tktph-avd` |
| Location | `southeastasia` |
| VM Prefix | `tktph-sh` |
| VM Count | `2` |
| VM Size | `Standard_D4s_v5` |
| Host Pool | `tktph-hp` |
| Workspace | `tktph-ws` |
| Storage Account | `sttktphfslogix` |
| User Prefix | `ph-consultant-` |
| User Count | `4` |

---

## Troubleshooting Quick Reference

| Issue | Check | Fix |
|-------|-------|-----|
| VMs not starting | `az vm list -g rg-tktph-avd -o table` | Start manually or check schedule |
| Users can't connect | `./validate-deployment.sh` | Check Conditional Access policy |
| FSLogix not working | Check storage connectivity | Verify SMB port 445 open |
| Logs not appearing | Check Azure Monitor Agent | Re-run `setup-session-logging.sh` |

---

## Files Structure

```
tkt-azure-platform-v4/
├── scripts/
│   ├── deploy-avd-platform-v4.sh      # Main orchestrator
│   ├── setup-session-host-hardening.sh
│   ├── setup-entra-id-automation.sh
│   ├── setup-fslogix-profiles.sh
│   ├── setup-vm-schedule.sh           # Optional: auto start/stop
│   ├── setup-session-logging.sh       # Optional: activity logging
│   ├── validate-deployment.sh
│   └── generate-deployment-report.sh
├── docs/
│   ├── v4-architecture-notes.md
│   ├── v4-known-issues.md
│   ├── v4-migration-guide.md
│   └── TESTING.md
├── templates/
│   ├── graph-api-user-template.json
│   ├── conditional-access-policy.json
│   └── deployment-report-template.md
├── AI-AGENT-CONTEXT.md                 # This file
└── README.md
```

---

## Important Notes

1. **All scripts support `--dry-run`** - always preview before making changes
2. **Scripts are idempotent** - safe to re-run, they skip existing resources
3. **Brussels timezone** - schedule uses Europe/Brussels, not Philippines time
4. **Teramind is third-party** - requires separate account/subscription (~€25/user/month)
5. **Session logging is free** - uses built-in Windows events + Log Analytics

---

## Contact / Escalation

- **Platform Owner:** tom.tuerlings@tktconsulting.com
- **Azure Subscription:** [Check with `az account show`]
- **Documentation:** See `/docs` folder
