# TKT Consulting Philippines SAP Platform
## Technical Architecture Document

**Version:** 2.0  
**Date:** January 30, 2026  
**Classification:** Confidential  
**Author:** TKT Consulting  
**Review Status:** For Cloud Architect Review

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-27 | TKT Consulting | Initial architecture |
| 2.0 | 2026-01-30 | TKT Consulting | Added security controls: URL filtering, data protection, session recording |

---

## 1. Executive Summary

This document describes the technical architecture for TKT Consulting's Philippines SAP Platform—a secure, multi-tenant infrastructure enabling remote SAP consultants in the Philippines to deliver services to European customers.

### Key Design Principles

1. **Zero Trust Security** — No implicit trust; verify everything
2. **Data Sovereignty** — No customer data stored on consultant VMs
3. **Complete Auditability** — All actions logged and recordable
4. **Cost Efficiency** — Enterprise-grade security at SMB pricing
5. **Scalability** — 5-minute customer onboarding

### Architecture Highlights

| Aspect | Solution |
|--------|----------|
| Compute | Azure IaaS VMs (Windows Server 2022) |
| Network Security | Azure Firewall with URL whitelisting |
| Data Storage | Azure Files (no local VM storage) |
| Identity | Azure AD with MFA + Conditional Access |
| Monitoring | Log Analytics + Session Recording |
| Backup | Geo-redundant Recovery Services Vault |

---

## 2. Business Context

### 2.1 Use Case

TKT Consulting provides SAP consulting services using remote consultants based in the Philippines. Consultants access customer SAP environments (S/4HANA Public Cloud, SuccessFactors) via web browsers from Azure-hosted virtual machines.

### 2.2 Security Requirements

| Requirement | Rationale |
|-------------|-----------|
| URL Whitelisting | Consultants should only access approved SAP and business domains |
| No Local Data | Customer data must not persist on consultant VMs |
| Session Recording | Enable audit trail and quality assurance review |
| Geographic Restrictions | Access only from Philippines (consultants) and Belgium (administrators) |
| MFA Enforcement | Prevent credential-based attacks |

### 2.3 Compliance Framework

- **GDPR** — Data protection for EU customer data
- **ISO 27001 Aligned** — Security controls following best practices
- **Customer Audit Ready** — Full logging and evidence collection capability

---

## 3. Architecture Overview

### 3.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AZURE CLOUD (Southeast Asia)                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    Resource Group: rg-customer-001-ph                  │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      Virtual Network                             │  │  │
│  │  │                      10.1.0.0/16                                 │  │  │
│  │  │  ┌──────────────────────────────────────────────────────────┐   │  │  │
│  │  │  │              Subnet: snet-workstations                    │   │  │  │
│  │  │  │                   10.1.1.0/24                             │   │  │  │
│  │  │  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐             │   │  │  │
│  │  │  │  │ VM-001 │ │ VM-002 │ │ VM-003 │ │ VM-004 │             │   │  │  │
│  │  │  │  │  Lead  │ │Consult1│ │Consult2│ │Consult3│             │   │  │  │
│  │  │  │  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘             │   │  │  │
│  │  │  │      │          │          │          │                   │   │  │  │
│  │  │  │      └──────────┴────┬─────┴──────────┘                   │   │  │  │
│  │  │  │                      │                                    │   │  │  │
│  │  │  └──────────────────────┼────────────────────────────────────┘   │  │  │
│  │  │                         │                                        │  │  │
│  │  │  ┌──────────────────────▼────────────────────────────────────┐   │  │  │
│  │  │  │                 AZURE FIREWALL                             │   │  │  │
│  │  │  │              URL Filtering & Logging                       │   │  │  │
│  │  │  │  ┌─────────────────────────────────────────────────────┐   │   │  │  │
│  │  │  │  │ ALLOWED DOMAINS:                                     │   │   │  │  │
│  │  │  │  │  ✓ *.sapcloud.com, *.s4hana.cloud.sap               │   │   │  │  │
│  │  │  │  │  ✓ *.successfactors.com, *.sap.com                  │   │   │  │  │
│  │  │  │  │  ✓ *.microsoft.com, *.office365.com                 │   │   │  │  │
│  │  │  │  │  ✓ Customer-specific domains (configurable)         │   │   │  │  │
│  │  │  │  │  ✗ All other domains BLOCKED                        │   │   │  │  │
│  │  │  │  └─────────────────────────────────────────────────────┘   │   │  │  │
│  │  │  └───────────────────────┬────────────────────────────────────┘   │  │  │
│  │  │                          │                                        │  │  │
│  │  └──────────────────────────┼────────────────────────────────────────┘  │  │
│  │                             │                                           │  │
│  │  ┌──────────────────────────▼────────────────────────────────────────┐  │  │
│  │  │                        INTERNET                                    │  │  │
│  │  │              (Only whitelisted destinations)                       │  │  │
│  │  └───────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                         │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐  │  │
│  │  │  Azure Files    │  │  Log Analytics  │  │  Recovery Services      │  │  │
│  │  │  (Knowledge     │  │  (Monitoring +  │  │  Vault (Backup)         │  │  │
│  │  │   Base + Data)  │  │   Recordings)   │  │                         │  │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘

                    EXTERNAL ACCESS POINTS
    ┌─────────────────────────────────────────────────────────────────┐
    │                                                                 │
    │   ┌─────────────┐                         ┌─────────────┐      │
    │   │ Philippines │                         │   Belgium   │      │
    │   │ Consultants │                         │   Admins    │      │
    │   │   (RDP)     │                         │   (RDP)     │      │
    │   └──────┬──────┘                         └──────┬──────┘      │
    │          │                                       │             │
    │          │         ┌─────────────────┐          │             │
    │          └─────────►│  Azure AD      │◄─────────┘             │
    │                     │  + MFA         │                        │
    │                     │  + Conditional │                        │
    │                     │    Access      │                        │
    │                     └─────────────────┘                        │
    │                                                                 │
    └─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW DIAGRAM                               │
└──────────────────────────────────────────────────────────────────────────┘

    CONSULTANT                      AZURE                         CUSTOMER
    ──────────                      ─────                         ────────

   ┌─────────┐     RDP/TLS      ┌─────────┐    HTTPS Only     ┌─────────────┐
   │  Home   │ ───────────────► │   VM    │ ────────────────► │ SAP S/4HANA │
   │  (PH)   │    MFA Required  │         │  Via Azure FW     │   Cloud     │
   └─────────┘                  └────┬────┘                   └─────────────┘
                                     │
                                     │ NO LOCAL STORAGE
                                     │ (GPO Enforced)
                                     │
                                     ▼
                              ┌─────────────┐
                              │ Azure Files │ ◄─── Knowledge Base
                              │   Share     │ ◄─── Project Files  
                              │ (Encrypted) │ ◄─── Session Recordings
                              └─────────────┘
                                     │
                                     │ Immutable Policy
                                     │ (90-day retention)
                                     │
                                     ▼
                              ┌─────────────┐
                              │   Backup    │
                              │   Vault     │
                              │ (Geo-Rep)   │
                              └─────────────┘
```

---

## 4. Security Architecture

### 4.1 Network Security — URL Whitelisting

**Problem:** Remote consultants should only access approved business domains, not arbitrary internet sites.

**Solution:** Azure Firewall with Application Rules

| Rule Name | Priority | Target FQDNs | Action |
|-----------|----------|--------------|--------|
| Allow-SAP-Cloud | 100 | *.sapcloud.com, *.hana.ondemand.com, *.s4hana.cloud.sap, *.successfactors.com, *.sap.com | Allow |
| Allow-Microsoft | 200 | *.microsoft.com, *.microsoftonline.com, *.azure.com, *.office.com, *.office365.com, *.sharepoint.com, *.teams.microsoft.com | Allow |
| Allow-Customer-Specific | 300 | {Configured per customer} | Allow |
| Deny-All-Other | 65000 | * | Deny |

**Logging:** All allowed and denied requests logged to Log Analytics for audit.

**Alert Configuration:**
- Blocked URL attempt → Warning alert to administrator
- High volume blocked attempts → Critical alert (potential compromise)

### 4.2 Data Protection — No Local Storage

**Problem:** Customer data must not persist on consultant VMs.

**Solution:** Multi-layered enforcement

| Layer | Control | Implementation |
|-------|---------|----------------|
| Group Policy | Disable local storage | Redirect Desktop, Documents, Downloads to Azure Files |
| Group Policy | Block USB devices | Prevent data exfiltration via removable media |
| RDP Policy | Clipboard restriction | One-way inbound only (paste TO VM, not FROM) |
| RDP Policy | Drive redirection | Disabled — no access to consultant's local drives |
| RDP Policy | Printer redirection | Disabled — no local printing |
| Azure Files | Mandatory storage | All work files stored in cloud share |

**Group Policy Objects (GPO):**

```
Computer Configuration → Administrative Templates → System → Removable Storage Access
  ├─ All Removable Storage classes: Deny all access = Enabled
  
User Configuration → Administrative Templates → Windows Components → Remote Desktop Services
  ├─ Device and Resource Redirection
  │   ├─ Do not allow clipboard redirection = Enabled (or one-way via RDP settings)
  │   ├─ Do not allow drive redirection = Enabled
  │   └─ Do not allow printer redirection = Enabled

Folder Redirection (User Configuration → Policies → Windows Settings)
  ├─ Desktop → \\stcustomer001ph.file.core.windows.net\consultant-data\%USERNAME%\Desktop
  ├─ Documents → \\stcustomer001ph.file.core.windows.net\consultant-data\%USERNAME%\Documents
  └─ Downloads → \\stcustomer001ph.file.core.windows.net\consultant-data\%USERNAME%\Downloads
```

### 4.3 Session Recording & Monitoring

**Problem:** Need audit trail of consultant actions for compliance and quality assurance.

**Solution:** Windows Session Recording + Azure Storage

| Component | Purpose | Implementation |
|-----------|---------|----------------|
| Windows Event Forwarding | Capture user actions | Forward to Log Analytics |
| Screen Recording | Visual audit trail | Windows Steps Recorder or third-party agent |
| Storage | Immutable retention | Azure Blob with WORM policy |
| Access Control | Admin-only viewing | RBAC restricted to TKT-Administrators |

**Recording Options (Cost/Feature Trade-off):**

| Option | Monthly Cost | Features | Recommendation |
|--------|--------------|----------|----------------|
| **Azure Monitor + Steps Recorder** | ~€15 | Basic session capture, manual trigger | MVP/Budget |
| **Microsoft Defender for Cloud Apps** | ~€50/user | Session recording, DLP, CASB | Enterprise |
| **Teramind/ObserveIT** | ~€25/user | Full UAM, video recording, productivity analytics | Comprehensive |

**Recommended MVP Implementation:**

1. Enable Windows Event Collection (Process creation, file access, network connections)
2. Configure Azure Monitor Agent on all VMs
3. Create custom workbooks for activity dashboards
4. Implement scheduled exports to immutable blob storage

### 4.4 Identity & Access Management

**Azure AD Configuration:**

```
Conditional Access Policies:
├─ Policy: Philippines-Consultants-MFA
│   ├─ Users: Customer-001-Philippines-SAP-Team
│   ├─ Cloud Apps: All cloud apps
│   ├─ Conditions: Any location
│   └─ Grant: Require MFA
│
├─ Policy: Admin-Access-Restricted
│   ├─ Users: TKT-Administrators
│   ├─ Cloud Apps: Azure Management
│   ├─ Conditions: Named locations (Belgium only)
│   └─ Grant: Require MFA + Compliant device
│
└─ Policy: Block-Legacy-Auth
    ├─ Users: All users
    ├─ Cloud Apps: All cloud apps
    ├─ Conditions: Client apps (Legacy authentication)
    └─ Grant: Block
```

**RBAC Roles:**

| Role | Scope | Permissions |
|------|-------|-------------|
| SAP Consultant | Assigned VM only | VM Start/Stop, Azure Files Read/Write |
| Team Lead | Customer resource group | VM Start/Stop, Azure Files Full Control, Monitoring Read |
| TKT Administrator | Subscription | Owner (emergency access only, PIM-protected) |

---

## 5. Infrastructure Components

### 5.1 Compute — Virtual Machines

| Specification | Value | Justification |
|---------------|-------|---------------|
| SKU | Standard_D4s_v3 | 4 vCPU, 16GB RAM — sufficient for browser-based SAP access |
| OS | Windows Server 2022 Datacenter | GPO support, security updates, RDS licensing |
| OS Disk | 127GB Premium SSD | Performance for OS and applications |
| Data Disks | None | All data on Azure Files |
| Availability | Single VM per consultant | No HA required — consultants can use alternate VM |

**VM Hardening:**
- Windows Defender enabled with cloud protection
- Windows Firewall enabled (inbound RDP only)
- Automatic Windows Updates (Patch Tuesday + 7 days)
- No local administrator access for consultants

### 5.2 Storage — Azure Files

| Specification | Value |
|---------------|-------|
| SKU | Standard ZRS (Zone-Redundant) |
| Protocol | SMB 3.0 with encryption |
| Authentication | Azure AD Kerberos |
| Quota | 100GB per customer |

**File Share Structure:**

```
stcustomer001ph.file.core.windows.net
└─ consultant-data (SMB Share)
    ├─ ph-lead-001/
    │   ├─ Desktop/
    │   ├─ Documents/
    │   └─ Downloads/
    ├─ ph-consultant-001/
    ├─ ph-consultant-002/
    ├─ ph-consultant-003/
    └─ _shared/
        ├─ knowledge-base/
        ├─ templates/
        └─ project-files/
```

### 5.3 Networking

| Component | Configuration |
|-----------|---------------|
| Virtual Network | 10.{customer}.0.0/16 |
| Workstation Subnet | 10.{customer}.1.0/24 with Storage service endpoint |
| Azure Firewall | Standard SKU, SNAT for outbound |
| NSG | Inbound RDP from PH/BE only, deny all other |
| Public IPs | Static, Standard SKU |

### 5.4 Monitoring & Logging

**Log Analytics Workspace:**

| Data Source | Retention | Purpose |
|-------------|-----------|---------|
| Azure Activity Logs | 90 days | Resource changes audit |
| VM Performance | 30 days | Capacity planning |
| Windows Security Events | 90 days | Security audit |
| Azure Firewall Logs | 90 days | URL access audit |
| Custom Events | 90 days | Application-specific logging |

**Alerts:**

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| VM Offline | Heartbeat missing > 5 min | Critical | Email + SMS |
| High CPU | > 85% for 15 min | Warning | Email |
| Disk Space Low | < 10% free | Critical | Email |
| Firewall Block Spike | > 50 blocks in 5 min | Warning | Email |
| Failed Login Attempts | > 5 in 10 min | Critical | Email + SMS |

### 5.5 Backup & Disaster Recovery

| Component | RPO | RTO | Method |
|-----------|-----|-----|--------|
| Virtual Machines | 24 hours | 4 hours | Azure Backup (daily) |
| Azure Files | 4 hours | 1 hour | Azure Backup + Snapshots |
| Configuration | Real-time | 30 min | Infrastructure as Code (Git) |

**Recovery Services Vault:**
- Geo-redundant storage (Southeast Asia → East Asia)
- Soft delete enabled (14-day retention)
- Cross-region restore capability

---

## 6. Cost Analysis

### 6.1 Monthly Cost Breakdown (4 Consultants)

| Component | Unit Cost | Quantity | Total |
|-----------|-----------|----------|-------|
| Virtual Machines (D4s_v3) | €95 | 4 | €380 |
| Azure Firewall (Standard) | €125 | 1 | €125 |
| Azure Files (100GB ZRS) | €10 | 1 | €10 |
| Log Analytics (~10GB/month) | €15 | 1 | €15 |
| Backup (4 VMs + Files) | €60 | 1 | €60 |
| Screen Recording Storage | €15 | 1 | €15 |
| Public IPs (4 Static) | €15 | 4 | €15 |
| **TOTAL** | | | **€620** |
| **Per Consultant** | | | **€155** |

### 6.2 Cost Optimization Options

| Option | Savings | Trade-off |
|--------|---------|-----------|
| Reserved Instances (1-year) | €115/month (30%) | Upfront commitment |
| Azure Virtual Desktop instead of IaaS | €100/month | Different management model |
| Deallocate VMs outside business hours | €150/month | 50% uptime only |
| Web Application Firewall instead of Azure FW | €80/month | Less granular URL filtering |

### 6.3 Scaling Economics

| Customers | Consultants | Monthly Cost | Per Consultant |
|-----------|-------------|--------------|----------------|
| 1 | 4 | €620 | €155 |
| 5 | 20 | €2,500 | €125 |
| 10 | 40 | €4,800 | €120 |

*Note: Azure Firewall cost shared across customers in scaled deployments*

---

## 7. Operational Procedures

### 7.1 Customer Onboarding (5 minutes)

```bash
# Automated deployment script
./create-philippines-customer.sh <customer-number> "<customer-name>"

# Creates:
# - Resource group with full tagging
# - 4 VMs (deallocated, ready to start)
# - Azure Files share with folder structure
# - 4 Azure AD users + security group
# - NSG rules and networking
# - Backup policies
# - Monitoring alerts
```

### 7.2 Daily Operations

| Task | Frequency | Method |
|------|-----------|--------|
| Review security alerts | Daily | Azure Monitor dashboard |
| Check backup status | Daily | Recovery Services Vault |
| Review blocked URLs | Weekly | Log Analytics query |
| Cost review | Weekly | Cost Management dashboard |
| Session recording review | On-demand | Blob storage access |

### 7.3 Incident Response

| Severity | Response Time | Escalation |
|----------|---------------|------------|
| Critical (VM down, security breach) | 30 minutes | Immediate |
| High (Performance degraded) | 2 hours | Same day |
| Medium (Non-critical issue) | 4 hours | Next business day |
| Low (Question, enhancement) | 24 hours | Within week |

---

## 8. Compliance & Audit

### 8.1 GDPR Compliance

| Requirement | Implementation |
|-------------|----------------|
| Data minimization | No customer data stored on VMs |
| Access control | RBAC + MFA + Conditional Access |
| Audit trail | Log Analytics + Session Recording |
| Data residency | Southeast Asia region |
| Right to erasure | Azure Files deletion + backup expiry |

### 8.2 Audit Evidence

| Audit Question | Evidence Location |
|----------------|-------------------|
| Who accessed the system? | Azure AD Sign-in Logs |
| What URLs were accessed? | Azure Firewall Logs |
| What files were modified? | Azure Files audit logs |
| What actions were taken? | Session recordings |
| Are backups successful? | Recovery Services Vault logs |
| Is MFA enforced? | Conditional Access reports |

---

## 9. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Consultant accesses unauthorized site | Medium | High | Azure Firewall URL filtering |
| Data exfiltration via clipboard | Medium | High | RDP one-way clipboard policy |
| Credential theft | Low | Critical | MFA + Conditional Access |
| VM compromise | Low | High | Network isolation + monitoring |
| Data loss | Low | Critical | Geo-redundant backup |
| Insider threat | Low | High | Session recording + least privilege |

---

## 10. Future Roadmap

### Phase 1 (Current)
- ✅ Core infrastructure deployed
- ✅ Basic security controls
- 🔄 Azure Firewall implementation
- 🔄 GPO hardening

### Phase 2 (30 days)
- Session recording implementation
- Enhanced monitoring dashboards
- Customer 002 deployment

### Phase 3 (90 days)
- Azure Virtual Desktop evaluation
- Microsoft Defender for Cloud Apps
- Automated compliance reporting

### Phase 4 (6 months)
- Multi-region deployment
- Advanced threat protection
- SOC 2 Type II preparation

---

## 11. Appendices

### Appendix A: Azure Resource Naming Convention

```
{resource-type}-{customer}-{workload}-{environment}-{region}

Examples:
rg-customer001-sap-prod-sea     (Resource Group)
vm-ph-lead-001                  (Virtual Machine)
vnet-customer001-ph             (Virtual Network)
afw-customer001-ph              (Azure Firewall)
stcustomer001ph                 (Storage Account - no hyphens)
law-customer001-ph              (Log Analytics Workspace)
rsv-customer001-ph              (Recovery Services Vault)
```

### Appendix B: Tag Schema

| Tag | Purpose | Example |
|-----|---------|---------|
| Customer | Cost allocation | Customer-001 |
| Project | Project tracking | SAP-Consulting |
| Environment | Lifecycle stage | Production |
| CostCenter | Billing code | Customer-001-Philippines |
| Owner | Responsible party | yannick.deridder@tktconsulting.com |
| DataClassification | Security level | Confidential |
| Compliance | Regulatory framework | GDPR |
| BackupRequired | Backup policy | Yes |

### Appendix C: Contact Information

| Role | Contact | Responsibility |
|------|---------|----------------|
| Platform Owner | tom.tuerlings@tktconsulting.com | Architecture decisions |
| Operations | TKT Operations Team | Daily monitoring |
| Security | TKT Security Team | Incident response |
| Customer Escalation | Customer Success | SLA management |

---

**Document End**

*This document is confidential and intended for authorized personnel only.*
