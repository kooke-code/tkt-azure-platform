# TKT Philippines AVD Platform - Implementation Checklist
## Version 3.0 - Azure Virtual Desktop Deployment

**Version:** 3.0  
**Date:** February 1, 2026  
**Estimated Duration:** 3-4 hours  
**Prerequisites:** Azure subscription, M365 Business Premium licenses

---

## Pre-Deployment Checklist

### Requirements Validation (MANDATORY - Lesson from v2)

- [ ] **Requirements questionnaire completed**
  - [ ] Number of concurrent users confirmed: ____
  - [ ] Applications needed: Browser-based only / Desktop apps
  - [ ] Operating hours: ____ to ____ (timezone: ____)
  - [ ] Data storage requirements: OneDrive sufficient / Need shared drives
  - [ ] Compliance requirements: GDPR / ISO 27001 / Other: ____

- [ ] **Cost estimate approved**
  - [ ] Stakeholder signed off on €220/month estimate
  - [ ] Budget code confirmed: ____

- [ ] **Azure prerequisites verified**
  ```bash
  # Run these checks
  az account show  # Verify login
  az provider show -n Microsoft.DesktopVirtualization  # AVD provider
  az provider show -n Microsoft.Compute  # Compute provider
  ```

- [ ] **M365 licenses available**
  - [ ] 4× M365 Business Premium licenses purchased
  - [ ] License assignment permissions confirmed

---

## Phase 1: Networking (30 minutes)

### 1.1 Create Resource Group

- [ ] Create resource group
  ```bash
  az group create \
    --name rg-tktph-avd-prod-sea \
    --location southeastasia \
    --tags Environment=Production Project=TKT-Philippines Owner=tom.tuerlings@tktconsulting.com
  ```

### 1.2 Create Virtual Network

- [ ] Create VNet
  ```bash
  az network vnet create \
    --resource-group rg-tktph-avd-prod-sea \
    --name vnet-tktph-avd-sea \
    --address-prefix 10.2.0.0/16 \
    --subnet-name snet-avd \
    --subnet-prefix 10.2.1.0/24
  ```

- [ ] Add Storage service endpoint
  ```bash
  az network vnet subnet update \
    --resource-group rg-tktph-avd-prod-sea \
    --vnet-name vnet-tktph-avd-sea \
    --name snet-avd \
    --service-endpoints Microsoft.Storage
  ```

### 1.3 Create Network Security Group

- [ ] Create NSG
  ```bash
  az network nsg create \
    --resource-group rg-tktph-avd-prod-sea \
    --name nsg-tktph-avd
  ```

- [ ] Add outbound rules (AVD, Storage, DNS, KMS)
- [ ] Add deny-all inbound rule
- [ ] Associate NSG with subnet

### 1.4 Validation

- [ ] **SMOKE TEST:** Verify VNet created with correct address space
- [ ] **SMOKE TEST:** Verify NSG rules applied
- [ ] **SMOKE TEST:** No public IPs created

---

## Phase 2: Storage & Monitoring (30 minutes)

### 2.1 Create Storage Account for FSLogix

- [ ] Create premium file storage account
  ```bash
  az storage account create \
    --resource-group rg-tktph-avd-prod-sea \
    --name sttktphfslogix \
    --kind FileStorage \
    --sku Premium_LRS \
    --location southeastasia \
    --https-only true \
    --min-tls-version TLS1_2
  ```

- [ ] Create FSLogix file share
  ```bash
  az storage share-rm create \
    --resource-group rg-tktph-avd-prod-sea \
    --storage-account sttktphfslogix \
    --name fslogix-profiles \
    --quota 100
  ```

- [ ] Configure Azure AD authentication for file share
- [ ] Set RBAC permissions (SMB Contributor for AVD users)

### 2.2 Create Log Analytics Workspace

- [ ] Create workspace
  ```bash
  az monitor log-analytics workspace create \
    --resource-group rg-tktph-avd-prod-sea \
    --workspace-name law-tktph-avd-sea \
    --location southeastasia \
    --retention-time 30
  ```

### 2.3 Validation

- [ ] **SMOKE TEST:** Storage account accessible via Azure portal
- [ ] **SMOKE TEST:** File share created with 100GB quota
- [ ] **SMOKE TEST:** Log Analytics workspace shows "Connected"

---

## Phase 3: AVD Control Plane (30 minutes)

### 3.1 Create Workspace

- [ ] Create AVD workspace
  ```bash
  az desktopvirtualization workspace create \
    --resource-group rg-tktph-avd-prod-sea \
    --name tktph-ws \
    --location southeastasia \
    --friendly-name "TKT Philippines Workspace"
  ```

### 3.2 Create Host Pool

- [ ] Create pooled host pool
  ```bash
  az desktopvirtualization hostpool create \
    --resource-group rg-tktph-avd-prod-sea \
    --name tktph-hp \
    --location southeastasia \
    --host-pool-type Pooled \
    --load-balancer-type BreadthFirst \
    --max-session-limit 2 \
    --preferred-app-group-type Desktop \
    --start-vm-on-connect true
  ```

- [ ] Generate registration token (valid for 24 hours)
  ```bash
  az desktopvirtualization hostpool update \
    --resource-group rg-tktph-avd-prod-sea \
    --name tktph-hp \
    --registration-info expiration-time="$(date -u -d '+24 hours' '+%Y-%m-%dT%H:%M:%SZ')" registration-token-operation="Update"
  ```

### 3.3 Create Application Group

- [ ] Create desktop application group
  ```bash
  az desktopvirtualization applicationgroup create \
    --resource-group rg-tktph-avd-prod-sea \
    --name tktph-dag \
    --location southeastasia \
    --host-pool-arm-path "/subscriptions/{sub}/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.DesktopVirtualization/hostpools/tktph-hp" \
    --application-group-type Desktop \
    --friendly-name "TKT Philippines Desktop"
  ```

- [ ] Associate application group with workspace

### 3.4 Configure Diagnostics

- [ ] Enable diagnostics on host pool → Log Analytics
- [ ] Enable diagnostics on workspace → Log Analytics

### 3.5 Validation

- [ ] **SMOKE TEST:** Workspace visible in Azure portal
- [ ] **SMOKE TEST:** Host pool shows "Pooled" type
- [ ] **SMOKE TEST:** Registration token generated (save securely!)

---

## Phase 4: Session Hosts (60 minutes)

### 4.1 Deploy Session Host VMs

- [ ] Deploy VM 1: vm-tktph-01
  ```bash
  az vm create \
    --resource-group rg-tktph-avd-prod-sea \
    --name vm-tktph-01 \
    --image MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest \
    --size Standard_D4s_v5 \
    --admin-username avdadmin \
    --admin-password <SECURE_PASSWORD> \
    --vnet-name vnet-tktph-avd-sea \
    --subnet snet-avd \
    --public-ip-address "" \
    --nsg ""
  ```

- [ ] Deploy VM 2: vm-tktph-02 (same config)

### 4.2 Install AVD Agent

- [ ] Connect to each VM via Azure Bastion (temporary) or Serial Console
- [ ] Download and install AVD Agent
  - URL: https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv
- [ ] Download and install AVD Bootloader
  - URL: https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH
- [ ] Enter registration token during agent installation

### 4.3 Configure FSLogix

- [ ] Install FSLogix on each VM
  - Download: https://aka.ms/fslogix_download
- [ ] Configure FSLogix registry settings:
  ```
  HKLM\SOFTWARE\FSLogix\Profiles
    Enabled = 1
    VHDLocations = \\sttktphfslogix.file.core.windows.net\fslogix-profiles
    DeleteLocalProfileWhenVHDShouldApply = 1
    SizeInMBs = 10240
  ```
- [ ] Configure FSLogix antivirus exclusions

### 4.4 Install Applications (if needed)

- [ ] Microsoft Edge (usually pre-installed)
- [ ] Any customer-specific applications

### 4.5 Validation

- [ ] **SMOKE TEST:** Both VMs show "Available" in host pool
- [ ] **SMOKE TEST:** VMs have no public IP addresses
- [ ] **SMOKE TEST:** FSLogix configured (check registry)
- [ ] **CRITICAL TEST:** Test network connectivity from VM
  ```powershell
  # Run on each VM
  Test-NetConnection -ComputerName www.microsoft.com -Port 443
  Test-NetConnection -ComputerName sttktphfslogix.file.core.windows.net -Port 445
  Resolve-DnsName www.sap.com
  ```

---

## Phase 5: Identity & Access (30 minutes)

### 5.1 Create Security Group

- [ ] Create Entra ID security group: TKT-Philippines-AVD-Users

### 5.2 Create/Configure User Accounts

- [ ] Create user: ph-consultant-001@tktconsulting.com
- [ ] Create user: ph-consultant-002@tktconsulting.com
- [ ] Create user: ph-consultant-003@tktconsulting.com
- [ ] Create user: ph-consultant-004@tktconsulting.com
- [ ] Add all users to security group
- [ ] Assign M365 Business Premium licenses

### 5.3 Assign Application Group Access

- [ ] Assign security group to application group (tktph-dag)
  ```bash
  az role assignment create \
    --assignee-object-id <GROUP_OBJECT_ID> \
    --role "Desktop Virtualization User" \
    --scope "/subscriptions/{sub}/resourceGroups/rg-tktph-avd-prod-sea/providers/Microsoft.DesktopVirtualization/applicationgroups/tktph-dag"
  ```

### 5.4 Configure Conditional Access

- [ ] Create policy: Require MFA for AVD
  - Users: TKT-Philippines-AVD-Users
  - Apps: Windows Virtual Desktop (9cdead84-a844-4324-93f2-b2e6bb768d07)
  - Grant: Require MFA

- [ ] Create policy: Block legacy authentication
  - Users: All users
  - Client apps: Legacy authentication clients
  - Grant: Block

### 5.5 Validation

- [ ] **SMOKE TEST:** Users appear in security group
- [ ] **SMOKE TEST:** Licenses assigned successfully
- [ ] **SMOKE TEST:** Conditional Access policies enabled

---

## Phase 6: Automation & Alerts (30 minutes)

### 6.1 Configure Auto-Shutdown

- [ ] Deploy Start/Stop VMs v2 solution
  - Start time: 08:00 PHT (00:00 UTC)
  - Stop time: 18:00 PHT (10:00 UTC)
  - Days: Monday-Friday
  - Scope: vm-tktph-01, vm-tktph-02

### 6.2 Create Action Group

- [ ] Create action group: ag-tktph-avd
  - Email receiver: tom.tuerlings@tktconsulting.com

### 6.3 Create Alerts

- [ ] Alert: Session host unavailable (heartbeat missing > 5 min) - Severity 0
- [ ] Alert: High CPU (> 85% for 15 min) - Severity 2
- [ ] Alert: Connection failures (> 5 in 10 min) - Severity 2

### 6.4 Validation

- [ ] **SMOKE TEST:** Auto-shutdown schedule visible in Azure
- [ ] **SMOKE TEST:** Test alert fires (trigger manually if possible)
- [ ] **SMOKE TEST:** Email notification received

---

## Phase 7: Final Validation (30 minutes)

### 7.1 User Login Test

- [ ] Open https://rdweb.wvd.microsoft.com/arm/webclient
- [ ] Sign in as ph-consultant-001@tktconsulting.com
- [ ] Verify MFA prompt appears
- [ ] Complete MFA registration
- [ ] Click on "TKT Philippines Desktop"
- [ ] Verify desktop loads within 60 seconds
- [ ] **CRITICAL:** Test SAP access (open browser, navigate to SAP URL)

### 7.2 FSLogix Profile Test

- [ ] Create a test file on Desktop
- [ ] Sign out
- [ ] Sign in again (may get different VM)
- [ ] Verify test file is still present

### 7.3 OneDrive Test

- [ ] Verify OneDrive sync configured
- [ ] Create file in OneDrive folder
- [ ] Verify sync to cloud

### 7.4 Auto-Shutdown Test

- [ ] Verify VMs are running during business hours
- [ ] Wait for shutdown time (or manually trigger)
- [ ] Verify VMs deallocate
- [ ] Verify "Start VM on Connect" works when user tries to connect

### 7.5 Monitoring Test

- [ ] Check AVD Insights workbook
- [ ] Verify session data appearing
- [ ] Verify connection logs present

---

## Post-Deployment

### Documentation

- [ ] Update architecture document with actual resource IDs
- [ ] Document any deviations from standard template
- [ ] Record registration token expiration date

### Handover

- [ ] Send welcome emails to all users with:
  - Web client URL
  - MFA registration instructions
  - OneDrive setup guide
  - Support contact information

- [ ] Schedule 15-minute onboarding call with each user

### Backup

- [ ] Commit all scripts to Git repository
- [ ] Export ARM templates for disaster recovery
- [ ] Document rollback procedure

---

## Rollback Procedure

If critical issues discovered:

```bash
# Delete all resources (30 seconds)
az group delete --name rg-tktph-avd-prod-sea --yes --no-wait

# Resources to manually clean up:
# - Entra ID users (if newly created)
# - Entra ID security group
# - Conditional Access policies
# - M365 license assignments
```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployer | | | |
| Technical Reviewer | | | |
| Business Owner | | | |

---

**Checklist Complete - Ready for Production Use**
