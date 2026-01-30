# TKT Philippines SAP Platform - Implementation Checklist
## Security Enhancement Deployment Guide

**Version:** 1.0  
**Date:** January 30, 2026  
**Status:** Ready for Implementation

---

## Pre-Implementation Requirements

### Azure Prerequisites
- [ ] Azure subscription with sufficient quota
- [ ] Owner or Contributor role on subscription
- [ ] Azure CLI installed and authenticated (`az login`)
- [ ] Resource providers registered:
  - [ ] Microsoft.Network
  - [ ] Microsoft.Compute
  - [ ] Microsoft.Storage
  - [ ] Microsoft.OperationalInsights

### Verification Commands
```bash
# Check Azure CLI authentication
az account show

# Verify subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Register required providers
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Storage
```

---

## Phase 1: Network Security (Azure Firewall)

### 1.1 Create Azure Firewall Subnet
- [ ] Add AzureFirewallSubnet to existing VNet (minimum /26)
- [ ] Verify no NSG attached to firewall subnet

### 1.2 Deploy Azure Firewall
- [ ] Create public IP for firewall
- [ ] Deploy Azure Firewall Standard SKU
- [ ] Configure diagnostic settings to Log Analytics

### 1.3 Configure Application Rules
- [ ] Create rule collection for SAP domains
- [ ] Create rule collection for Microsoft services
- [ ] Create deny-all default rule
- [ ] Test connectivity to allowed domains
- [ ] Verify blocked domains are denied

### 1.4 Update Route Table
- [ ] Create route table with default route to firewall
- [ ] Associate route table with workstation subnet
- [ ] Verify VM traffic flows through firewall

### 1.5 Verification Tests
- [ ] From VM: Access https://www.sap.com ✓
- [ ] From VM: Access https://portal.azure.com ✓
- [ ] From VM: Access https://www.google.com ✗ (should be blocked)
- [ ] Check firewall logs in Log Analytics

---

## Phase 2: Storage Configuration

### 2.1 Azure Files Setup
- [ ] Create file share "consultant-data" (100GB quota)
- [ ] Enable Azure AD authentication for file share
- [ ] Create folder structure for each user
- [ ] Configure RBAC permissions

### 2.2 Storage Security
- [ ] Enable "Secure transfer required"
- [ ] Set minimum TLS version to 1.2
- [ ] Disable public blob access
- [ ] Configure private endpoint (optional, adds cost)
- [ ] Enable soft delete for file shares

### 2.3 Mount Configuration
- [ ] Document mount command for VMs
- [ ] Test mounting from each VM
- [ ] Verify read/write permissions

---

## Phase 3: VM Hardening (Group Policy)

### 3.1 Create GPO Infrastructure
- [ ] Decide: Azure AD Domain Services vs Local GPO
- [ ] For Local GPO: Configure on each VM
- [ ] For AADDS: Deploy domain services (adds ~€100/month)

### 3.2 Folder Redirection GPO
- [ ] Redirect Desktop to Azure Files
- [ ] Redirect Documents to Azure Files
- [ ] Redirect Downloads to Azure Files
- [ ] Test redirection works correctly

### 3.3 Security Restrictions GPO
- [ ] Block USB storage devices
- [ ] Disable local drive access
- [ ] Configure Windows Firewall rules
- [ ] Disable unnecessary services

### 3.4 RDP Restrictions
- [ ] Disable clipboard redirection (or one-way)
- [ ] Disable drive redirection
- [ ] Disable printer redirection
- [ ] Configure session timeout (8 hours)

### 3.5 Verification Tests
- [ ] USB device insertion blocked
- [ ] Cannot save to local C: drive user folders
- [ ] Files save to Azure Files automatically
- [ ] Cannot copy from VM to local clipboard

---

## Phase 4: Monitoring & Session Recording

### 4.1 Log Analytics Enhancement
- [ ] Enable Windows Security Events collection
- [ ] Enable Windows Event Logs (Application, System)
- [ ] Configure Azure Firewall diagnostic logs
- [ ] Set retention to 90 days

### 4.2 Alert Rules
- [ ] Create alert: Firewall blocked requests > 50 in 5 min
- [ ] Create alert: Failed login attempts > 5 in 10 min
- [ ] Create alert: VM heartbeat missing > 5 min
- [ ] Configure action group with email notifications

### 4.3 Session Recording (Choose One)

#### Option A: Basic (Azure Monitor + Windows Events)
- [ ] Enable Process Creation auditing
- [ ] Enable File System auditing
- [ ] Configure Azure Monitor Agent
- [ ] Create Log Analytics workbook for activity

#### Option B: Windows Session Recording
- [ ] Configure Windows Remote Desktop Session Recording
- [ ] Set up storage container for recordings
- [ ] Configure immutable blob policy
- [ ] Test recording playback

#### Option C: Third-Party (Teramind/ObserveIT)
- [ ] Evaluate vendors and pricing
- [ ] Deploy agent to VMs
- [ ] Configure recording policies
- [ ] Set up admin console access

---

## Phase 5: Identity & Access

### 5.1 Conditional Access Policies
- [ ] Create policy: Require MFA for Philippines team
- [ ] Create policy: Block legacy authentication
- [ ] Create policy: Restrict admin access to Belgium
- [ ] Enable policies in report-only mode first
- [ ] Monitor sign-in logs for issues
- [ ] Switch to enforced mode

### 5.2 RBAC Verification
- [ ] Verify consultants cannot delete VMs
- [ ] Verify consultants can start/stop own VM
- [ ] Verify consultants can access Azure Files
- [ ] Verify team lead has appropriate elevated access

---

## Phase 6: Backup & Recovery

### 6.1 VM Backup
- [ ] Verify backup policy is applied to all VMs
- [ ] Confirm daily backup schedule
- [ ] Test restore to verify backups work

### 6.2 Azure Files Backup
- [ ] Enable backup for consultant-data share
- [ ] Configure retention policy
- [ ] Test file restore

---

## Post-Implementation Validation

### Security Validation Checklist
| Test | Expected Result | Pass/Fail |
|------|-----------------|-----------|
| Access sap.com from VM | Allowed | |
| Access google.com from VM | Blocked | |
| Insert USB drive | Blocked | |
| Copy text from VM to local | Blocked | |
| Save file to Desktop | Saves to Azure Files | |
| Login without MFA | Blocked | |
| Delete VM as consultant | Blocked | |

### Documentation Updates
- [ ] Update architecture document with actual resource IDs
- [ ] Document any deviations from plan
- [ ] Create runbook for common operations
- [ ] Update cost tracking spreadsheet

---

## Rollback Procedures

### If Azure Firewall Causes Issues
```bash
# Remove route table association (restores direct internet)
az network vnet subnet update \
  --resource-group rg-customer-001-philippines \
  --vnet-name vnet-customer-001-ph \
  --name snet-workstations \
  --route-table ""
```

### If GPO Causes Issues
- Login as local administrator
- Run `gpupdate /force` to clear policies
- Or restore VM from backup

---

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Network Security | 2-4 hours | None |
| Phase 2: Storage Config | 1-2 hours | None |
| Phase 3: VM Hardening | 2-4 hours | Phase 2 |
| Phase 4: Monitoring | 1-2 hours | Phase 1 |
| Phase 5: Identity | 1-2 hours | None |
| Phase 6: Backup | 30 min | None |
| **Total** | **8-15 hours** | |

---

## Support Contacts

| Issue Type | Contact | Method |
|------------|---------|--------|
| Azure Platform | Microsoft Support | Azure Portal |
| Architecture Questions | Cloud Architect | Email |
| Implementation Issues | TKT Operations | Teams |

---

**Checklist Complete - Ready for Implementation**
