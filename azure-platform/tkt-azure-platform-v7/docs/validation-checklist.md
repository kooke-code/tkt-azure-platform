# TKT Philippines AVD Platform - Validation Checklist
## Post-Deployment Smoke Tests & Acceptance Criteria

**Version:** 3.0  
**Date:** February 1, 2026  
**Purpose:** Ensure deployment is complete and functional before handover

---

## Critical Lesson from v2

> **NEVER mark deployment complete until ALL smoke tests pass!**
> 
> In v2, we deployed infrastructure but didn't validate network connectivity.
> The VM couldn't reach the internet, making it useless. This checklist
> ensures we don't repeat that mistake.

---

## Test Summary

| Category | Tests | Pass Criteria |
|----------|-------|---------------|
| Network | 5 | All must pass |
| Identity | 4 | All must pass |
| AVD | 6 | All must pass |
| Storage | 4 | All must pass |
| Monitoring | 3 | All must pass |
| Automation | 2 | All must pass |
| **Total** | **24** | **24/24 required** |

---

## 1. Network Connectivity Tests (CRITICAL)

### Test 1.1: DNS Resolution
```powershell
# Run on each session host
Resolve-DnsName www.microsoft.com
Resolve-DnsName login.microsoftonline.com
Resolve-DnsName www.sap.com
```

| VM | Result | Pass/Fail |
|----|--------|-----------|
| vm-tktph-01 | | |
| vm-tktph-02 | | |

**Pass Criteria:** All DNS queries return IP addresses

### Test 1.2: HTTPS Connectivity (Port 443)
```powershell
Test-NetConnection -ComputerName www.microsoft.com -Port 443
Test-NetConnection -ComputerName rdweb.wvd.microsoft.com -Port 443
```

| VM | microsoft.com | rdweb.wvd | Pass/Fail |
|----|---------------|-----------|-----------|
| vm-tktph-01 | | | |
| vm-tktph-02 | | | |

**Pass Criteria:** TcpTestSucceeded = True for all

### Test 1.3: Storage Connectivity (Port 445)
```powershell
Test-NetConnection -ComputerName sttktphfslogix.file.core.windows.net -Port 445
```

| VM | Result | Pass/Fail |
|----|--------|-----------|
| vm-tktph-01 | | |
| vm-tktph-02 | | |

### Test 1.4: No Public IP
```bash
az vm list-ip-addresses --resource-group rg-tktph-avd-prod-sea --output table
```

| VM | Public IP | Pass/Fail |
|----|-----------|-----------|
| vm-tktph-01 | None | |
| vm-tktph-02 | None | |

### Test 1.5: SAP Cloud Access
```powershell
Test-NetConnection -ComputerName www.sap.com -Port 443
```

| VM | SAP Reachable | Pass/Fail |
|----|---------------|-----------|
| vm-tktph-01 | | |
| vm-tktph-02 | | |

---

## 2. Identity & Authentication Tests

### Test 2.1: User Exists in Entra ID
```bash
az ad user show --id ph-consultant-001@tktconsulting.com
```

| User | Exists | License | Pass/Fail |
|------|--------|---------|-----------|
| ph-consultant-001 | | | |
| ph-consultant-002 | | | |
| ph-consultant-003 | | | |
| ph-consultant-004 | | | |

### Test 2.2: Security Group Membership
| User | In AVD-Users Group | Pass/Fail |
|------|--------------------|-----------|
| ph-consultant-001 | | |
| ph-consultant-002 | | |
| ph-consultant-003 | | |
| ph-consultant-004 | | |

### Test 2.3: MFA Registration
| User | MFA Registered | Pass/Fail |
|------|----------------|-----------|
| ph-consultant-001 | | |
| ph-consultant-002 | | |
| ph-consultant-003 | | |
| ph-consultant-004 | | |

### Test 2.4: Conditional Access Active
1. Open https://rdweb.wvd.microsoft.com/arm/webclient
2. Sign in as test user
3. Verify MFA prompt appears

| Test | Result | Pass/Fail |
|------|--------|-----------|
| MFA prompt shown | | |

---

## 3. AVD Functionality Tests

### Test 3.1: Host Pool Status
```bash
az desktopvirtualization hostpool show --resource-group rg-tktph-avd-prod-sea --name tktph-hp
```

| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Type | Pooled | | |
| Max sessions | 2 | | |

### Test 3.2: Session Host Health
```bash
az desktopvirtualization sessionhost list --resource-group rg-tktph-avd-prod-sea --host-pool-name tktph-hp
```

| Host | Status | Pass/Fail |
|------|--------|-----------|
| vm-tktph-01 | Available | |
| vm-tktph-02 | Available | |

### Test 3.3: User Can See Desktop
1. Sign in to web client
2. Verify desktop icon appears

| Test | Result | Pass/Fail |
|------|--------|-----------|
| Desktop visible | | |

### Test 3.4: User Can Connect
1. Click desktop icon
2. Wait for desktop to load

| Test | Metric | Pass/Fail |
|------|--------|-----------|
| Connection time | < 60s | |
| Desktop loads | | |

### Test 3.5: Load Balancing Works
| User | Assigned Host | Pass/Fail |
|------|---------------|-----------|
| User 1 | | |
| User 2 | | |

### Test 3.6: Reconnection Works
| Test | Result | Pass/Fail |
|------|--------|-----------|
| Session preserved | | |

---

## 4. Storage Tests

### Test 4.1: FSLogix Profile Creation
| User | Profile VHD Created | Pass/Fail |
|------|---------------------|-----------|
| ph-consultant-001 | | |

### Test 4.2: Profile Roaming
| Test | Result | Pass/Fail |
|------|--------|-----------|
| Files persist across hosts | | |

### Test 4.3: OneDrive Sync
| Test | Result | Pass/Fail |
|------|--------|-----------|
| OneDrive connected | | |
| Files syncing | | |

### Test 4.4: Storage Quota
| Check | Expected | Actual | Pass/Fail |
|-------|----------|--------|-----------|
| Quota | 100 GB | | |

---

## 5. Monitoring Tests

### Test 5.1: AVD Insights Data
| Data | Present | Pass/Fail |
|------|---------|-----------|
| Connection events | | |
| Session host health | | |

### Test 5.2: Alerts Configured
| Alert | State | Pass/Fail |
|-------|-------|-----------|
| SessionHost-Unavailable | | |
| High-CPU-Usage | | |
| Connection-Failures | | |

### Test 5.3: Action Group Test
| Test | Result | Pass/Fail |
|------|--------|-----------|
| Test email received | | |

---

## 6. Automation Tests

### Test 6.1: Auto-Shutdown Scheduled
| Setting | Expected | Actual | Pass/Fail |
|---------|----------|--------|-----------|
| Stop time | 18:00 PHT | | |
| Start time | 08:00 PHT | | |
| Days | Mon-Fri | | |

### Test 6.2: Start VM on Connect
| Test | Result | Pass/Fail |
|------|--------|-----------|
| VM auto-starts | | |
| Connection completes | | |

---

## Summary Scorecard

| Category | Passed | Failed | Status |
|----------|--------|--------|--------|
| Network | /5 | | |
| Identity | /4 | | |
| AVD | /6 | | |
| Storage | /4 | | |
| Monitoring | /3 | | |
| Automation | /2 | | |
| **Total** | **/24** | | |

---

## Go/No-Go Decision

- [ ] **ALL 24 tests passed** → Ready for production
- [ ] **Any test failed** → Fix issues before proceeding

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Technical Validator | | | |
| Business Owner | | | |

---

**All tests must pass before declaring deployment successful.**
