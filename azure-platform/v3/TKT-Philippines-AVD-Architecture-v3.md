# TKT Consulting Philippines SAP Platform
## Azure Virtual Desktop Architecture - Version 3.0

**Version:** 3.0  
**Date:** February 1, 2026  
**Classification:** Confidential  
**Status:** Production Ready

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-27 | TKT Consulting | Initial Windows Server architecture |
| 2.0 | 2026-01-30 | TKT Consulting | Added security controls (Firewall, hardening) |
| 3.0 | 2026-02-01 | TKT Consulting | **Complete redesign to AVD** - lessons learned applied |

---

## 1. Executive Summary

This document describes the Azure Virtual Desktop (AVD) architecture for TKT Consulting's Philippines SAP Platform. This is a complete redesign based on lessons learned from the v2 Windows Server deployment.

### Why AVD Instead of Windows Server VMs?

| Requirement | Windows Server VM | Azure Virtual Desktop |
|-------------|-------------------|----------------------|
| Multi-user sessions | Requires RDS CALs, complex | Native multi-session support |
| Browser-based SAP access | Works but overkill | Perfect fit |
| Business hours only | Manual start/stop | Auto-shutdown built-in |
| Cost for 4 users | €1,200/month (with Firewall) | €220/month |
| Management overhead | High (patching, security) | Low (managed service) |

### Architecture Highlights

| Component | Solution | Monthly Cost |
|-----------|----------|--------------|
| Compute | 2× D4s_v5 session hosts | €110 (8h/day) |
| Identity | Entra ID + M365 Business Premium | €80 (4 users) |
| Storage | Azure Files Premium (FSLogix) | €20 |
| Monitoring | AVD Insights + Log Analytics | €10 |
| **Total** | | **€220/month** |

**Cost per consultant: €55/month** (vs €150 budget = 63% under budget)

---

## 2. Architecture Overview

### 2.1 High-Level Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AZURE CLOUD (Southeast Asia)                          │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │              Resource Group: rg-tktph-avd-prod-sea                     │ │
│  │                                                                        │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    AVD Control Plane                            │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐    │  │ │
│  │  │  │  Workspace  │  │  Host Pool  │  │  Application Group   │    │  │ │
│  │  │  │  tktph-ws   │  │  tktph-hp   │  │  tktph-dag (Desktop) │    │  │ │
│  │  │  └─────────────┘  └──────┬──────┘  └──────────────────────┘    │  │ │
│  │  └──────────────────────────┼─────────────────────────────────────┘  │ │
│  │                             │                                        │ │
│  │  ┌──────────────────────────┼─────────────────────────────────────┐  │ │
│  │  │           Session Hosts (VNet: 10.2.0.0/16)                    │  │ │
│  │  │                          │                                     │  │ │
│  │  │    ┌─────────────────────┴─────────────────────┐              │  │ │
│  │  │    │         Subnet: snet-avd (10.2.1.0/24)    │              │  │ │
│  │  │    │                                           │              │  │ │
│  │  │    │   ┌──────────────┐   ┌──────────────┐    │              │  │ │
│  │  │    │   │ vm-tktph-01  │   │ vm-tktph-02  │    │              │  │ │
│  │  │    │   │ D4s_v5       │   │ D4s_v5       │    │              │  │ │
│  │  │    │   │ Win11 Multi  │   │ Win11 Multi  │    │              │  │ │
│  │  │    │   │ 2 sessions   │   │ 2 sessions   │    │              │  │ │
│  │  │    │   └──────────────┘   └──────────────┘    │              │  │ │
│  │  │    │                                           │              │  │ │
│  │  │    │   NSG: nsg-tktph-avd                     │              │  │ │
│  │  │    │   - Allow AVD control plane (443)        │              │  │ │
│  │  │    │   - Allow storage (445)                  │              │  │ │
│  │  │    │   - Deny all other inbound               │              │  │ │
│  │  │    └───────────────────────────────────────────┘              │  │ │
│  │  └────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐   │ │
│  │  │  Azure Files    │  │  Log Analytics  │  │  Automation Account │   │ │
│  │  │  Premium        │  │  Workspace      │  │  (Start/Stop VMs)   │   │ │
│  │  │  FSLogix        │  │  AVD Insights   │  │  08:00-18:00 PHT    │   │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────────┘   │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

                              USER ACCESS
    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │   Philippines Consultants              Belgium Administrators       │
    │   ┌─────────────────────┐              ┌─────────────────────┐     │
    │   │  AVD Web Client     │              │  AVD Windows Client │     │
    │   │  rdweb.wvd.microsoft│              │  or Web Client      │     │
    │   │  .com               │              │                     │     │
    │   └──────────┬──────────┘              └──────────┬──────────┘     │
    │              │                                    │                │
    │              └────────────┬───────────────────────┘                │
    │                           │                                        │
    │                    ┌──────▼──────┐                                 │
    │                    │  Entra ID   │                                 │
    │                    │  + MFA      │                                 │
    │                    │  Conditional│                                 │
    │                    │  Access     │                                 │
    │                    └─────────────┘                                 │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATA FLOW                                       │
└─────────────────────────────────────────────────────────────────────────────┘

    CONSULTANT                  AZURE                           SAP CLOUD
    ──────────                  ─────                           ─────────

   ┌─────────────┐   HTTPS    ┌───────────────┐   HTTPS    ┌─────────────────┐
   │  Browser    │ ─────────► │  AVD Gateway  │ ─────────► │  SAP S/4HANA    │
   │  (Home PC)  │   RDP/WS   │  (Microsoft)  │   via VM   │  Public Cloud   │
   └─────────────┘            └───────┬───────┘            └─────────────────┘
                                      │
                                      ▼
                              ┌───────────────┐
                              │ Session Host  │
                              │   (No data    │
                              │    stored)    │
                              └───────┬───────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
     ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
     │    OneDrive     │    │   SharePoint    │    │     FSLogix     │
     │  (User Files)   │    │  (Team Files)   │    │   (Profiles)    │
     │   1TB/user      │    │   Shared Docs   │    │   Azure Files   │
     └─────────────────┘    └─────────────────┘    └─────────────────┘

    KEY PRINCIPLE: No customer data stored on session hosts
    - Browser cache cleared on logoff
    - FSLogix profile contains only settings, not data
    - All work files in OneDrive/SharePoint (encrypted, backed up)
```

---

## 3. Component Specifications

### 3.1 AVD Control Plane (Microsoft-Managed)

| Component | Name | Purpose |
|-----------|------|---------|
| Workspace | tktph-ws | Entry point for users |
| Host Pool | tktph-hp | Pooled, breadth-first load balancing |
| Application Group | tktph-dag | Full desktop access |

**Host Pool Configuration:**
- Type: Pooled (shared desktops)
- Load Balancing: Breadth-first (distribute users evenly)
- Max Sessions per Host: 2 (conservative for SAP browser work)
- Validation Environment: No

### 3.2 Session Hosts

| Specification | Value | Justification |
|---------------|-------|---------------|
| Count | 2 | Redundancy - if one fails, all users can use the other |
| SKU | Standard_D4s_v5 | 4 vCPU, 16GB RAM - sufficient for 2 browser sessions |
| OS | Windows 11 Enterprise Multi-Session | Native AVD support, familiar UX |
| OS Disk | 128GB Premium SSD v2 | Fast boot, included in VM price |
| Data Disks | None | All data in OneDrive/Azure Files |
| Availability | No availability set | Cost optimization, acceptable for non-critical workload |

**Naming Convention:**
- vm-tktph-01, vm-tktph-02

### 3.3 Storage

| Component | Specification | Purpose |
|-----------|---------------|---------|
| Azure Files Premium | 100GB, LRS | FSLogix profile containers |
| OneDrive | 1TB per user (M365) | Personal file storage |
| SharePoint | 1TB shared (M365) | Team collaboration |

**FSLogix Configuration:**
- Profile type: VHDx
- Size limit: 10GB per user
- Cloud cache: Disabled (single region)
- Concurrent user access: Enabled

### 3.4 Networking

| Component | Configuration |
|-----------|---------------|
| VNet | vnet-tktph-avd-sea (10.2.0.0/16) |
| Subnet | snet-avd (10.2.1.0/24) |
| NSG | nsg-tktph-avd |
| DNS | Azure-provided (168.63.129.16) |
| Public IPs | None on session hosts |

**NSG Rules:**

| Priority | Name | Direction | Action | Source | Destination | Port |
|----------|------|-----------|--------|--------|-------------|------|
| 100 | Allow-AVD-Outbound | Outbound | Allow | VNet | AzureCloud | 443 |
| 110 | Allow-Storage | Outbound | Allow | VNet | Storage | 445 |
| 120 | Allow-DNS | Outbound | Allow | VNet | * | 53 |
| 130 | Allow-KMS | Outbound | Allow | VNet | * | 1688 |
| 4096 | Deny-All-Inbound | Inbound | Deny | * | * | * |

**Key Difference from v2:** No Azure Firewall! NSG is sufficient for AVD.

### 3.5 Identity & Access

| Component | Configuration |
|-----------|---------------|
| Identity Provider | Microsoft Entra ID |
| Licensing | M365 Business Premium (4 users) |
| MFA | Required via Conditional Access |
| Device Compliance | Not required (BYOD allowed) |

**Conditional Access Policies:**

| Policy | Users | Condition | Grant |
|--------|-------|-----------|-------|
| Require MFA for AVD | All AVD users | Windows Virtual Desktop | MFA required |
| Block legacy auth | All users | Legacy protocols | Block |

**User Accounts:**
- ph-consultant-001@tktconsulting.com
- ph-consultant-002@tktconsulting.com
- ph-consultant-003@tktconsulting.com
- ph-consultant-004@tktconsulting.com

### 3.6 Monitoring

| Component | Configuration |
|-----------|---------------|
| Log Analytics | law-tktph-avd-sea |
| AVD Insights | Enabled |
| Retention | 30 days (cost optimization) |

**Alerts:**

| Alert | Condition | Severity |
|-------|-----------|----------|
| Session host unavailable | Heartbeat missing > 5 min | Critical |
| High CPU | > 85% for 15 min | Warning |
| Low disk space | < 10GB free | Critical |
| User connection failures | > 5 in 10 min | Warning |

### 3.7 Auto-Shutdown (Cost Optimization)

| Setting | Value |
|---------|-------|
| Solution | Start/Stop VMs v2 |
| Start Time | 08:00 PHT (00:00 UTC) |
| Stop Time | 18:00 PHT (10:00 UTC) |
| Days | Monday-Friday |
| Weekend | Stopped |
| Savings | ~60% compute costs |

---

## 4. Cost Analysis

### 4.1 Monthly Cost Breakdown

| Component | Unit | Quantity | Unit Cost | Total |
|-----------|------|----------|-----------|-------|
| Session Hosts (D4s_v5) | VM-hour | 440 hrs (8h×22d×2) | €0.25 | €110 |
| Azure Files Premium | GB | 100 | €0.20 | €20 |
| M365 Business Premium | User | 4 | €20 | €80 |
| Log Analytics | GB | 5 | €2 | €10 |
| **Total** | | | | **€220** |
| **Per Consultant** | | | | **€55** |

### 4.2 Cost Comparison (v2 vs v3)

| Component | v2 (Server VM) | v3 (AVD) | Savings |
|-----------|----------------|----------|---------|
| Compute | €380 | €110 | €270 |
| Azure Firewall | €912 | €0 | €912 |
| Bastion | €100 | €0 | €100 |
| Storage | €20 | €20 | €0 |
| Monitoring | €15 | €10 | €5 |
| Identity | €0 | €80 | -€80 |
| Backup | €60 | €0* | €60 |
| **Total** | **€1,487** | **€220** | **€1,267 (85%)** |

*Backup included in M365 (OneDrive versioning, SharePoint retention)

### 4.3 Cost Optimization Opportunities

| Optimization | Current | Optimized | Savings |
|--------------|---------|-----------|---------|
| Reserved Instances (1yr) | €110 | €77 | €33 (30%) |
| Dev/Test subscription | €110 | €44 | €66 (60%) |
| Spot VMs (risky) | €110 | €33 | €77 (70%) |

---

## 5. Security Architecture

### 5.1 Security Controls

| Layer | Control | Implementation |
|-------|---------|----------------|
| Identity | MFA | Conditional Access policy |
| Identity | SSO | Entra ID + M365 integration |
| Network | Isolation | No public IPs, NSG deny-all inbound |
| Network | Encryption | TLS 1.2+ for all connections |
| Endpoint | Defender | Microsoft Defender for Endpoint (M365) |
| Data | Encryption | BitLocker (OS), Azure Storage encryption |
| Data | DLP | Microsoft Purview (optional) |

### 5.2 Comparison: Azure Firewall vs NSG for AVD

| Capability | Azure Firewall | NSG Only |
|------------|----------------|----------|
| URL filtering | ✓ | ✗ |
| Application rules | ✓ | ✗ |
| Threat intelligence | ✓ | ✗ |
| Central logging | ✓ | ✓ |
| Cost | €912/month | €0 |
| **Recommendation** | Overkill for 4 users | **Sufficient** |

**When to add Azure Firewall:**
- Customer requires URL filtering as compliance control
- Scaling beyond 20 users
- Multiple customer environments sharing infrastructure

### 5.3 Data Protection

| Data Type | Location | Protection |
|-----------|----------|------------|
| User profiles | Azure Files | Encryption at rest, AAD RBAC |
| Work files | OneDrive | Encryption, versioning, 93-day recycle |
| Team files | SharePoint | Encryption, retention policies |
| Browser cache | Session host | Cleared on logoff (FSLogix) |

---

## 6. Operational Procedures

### 6.1 User Onboarding

1. Create user in Entra ID
2. Assign M365 Business Premium license
3. Add to AVD application group
4. Send welcome email with:
   - Web client URL: https://rdweb.wvd.microsoft.com/arm/webclient
   - OneDrive setup instructions
   - MFA registration link

### 6.2 Daily Operations

| Task | Frequency | Method |
|------|-----------|--------|
| Check session host health | Daily | AVD Insights dashboard |
| Review connection failures | Daily | Log Analytics query |
| Monitor costs | Weekly | Cost Management |
| Apply Windows updates | Monthly | Maintenance window |

### 6.3 Troubleshooting

| Issue | Likely Cause | Resolution |
|-------|--------------|------------|
| "No resources available" | Both hosts down or at capacity | Start VMs or check auto-shutdown |
| Slow login | FSLogix profile large | Check profile size, clear temp files |
| Disconnections | Network issues | Check NSG, user's home internet |
| Application errors | Browser cache | Clear cache, sign out/in |

---

## 7. Disaster Recovery

### 7.1 Recovery Objectives

| Metric | Target | Current |
|--------|--------|---------|
| RTO (Recovery Time) | 4 hours | 1 hour (redeploy from IaC) |
| RPO (Data Loss) | 1 hour | Near-zero (OneDrive sync) |

### 7.2 Backup Strategy

| Component | Backup Method | Retention |
|-----------|---------------|-----------|
| Session hosts | None (stateless) | N/A - redeploy from image |
| FSLogix profiles | Azure Files snapshots | 7 days |
| User files | OneDrive versioning | 93 days |
| Team files | SharePoint retention | 93 days |
| Configuration | Git repository | Indefinite |

### 7.3 Disaster Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| Single host failure | 50% capacity | Users auto-failover to other host |
| Both hosts failure | Full outage | Redeploy from IaC (1 hour) |
| Azure region failure | Full outage | Deploy to alternate region (4 hours) |
| Entra ID outage | Cannot authenticate | Wait for Microsoft (rare) |

---

## 8. Governance & Compliance

### 8.1 Resource Tagging

| Tag | Value | Purpose |
|-----|-------|---------|
| Environment | Production | Lifecycle |
| Project | TKT-Philippines | Cost allocation |
| Owner | tom.tuerlings@tktconsulting.com | Accountability |
| CostCenter | TKTPH-001 | Billing |
| DataClassification | Confidential | Security |
| AutoShutdown | Enabled | Cost control |

### 8.2 Compliance Mapping

| Requirement | Control | Evidence |
|-------------|---------|----------|
| GDPR - Data minimization | No data on VMs | Architecture design |
| GDPR - Encryption | TLS + AES-256 | Azure compliance docs |
| GDPR - Access control | Entra ID + MFA | Conditional Access logs |
| GDPR - Audit trail | Log Analytics | 30-day retention |

---

## 9. Lessons Learned (v2 → v3)

### 9.1 What Went Wrong in v2

| Issue | Impact | How v3 Fixes It |
|-------|--------|-----------------|
| Wrong architecture (Server VM) | Complexity, cost | AVD designed for this use case |
| Azure Firewall overkill | €912/month waste | NSG only, add Firewall if needed |
| No connectivity validation | VM couldn't reach internet | Mandatory smoke tests in deployment |
| Cost estimation wrong | 10× over budget | Detailed calculator, all components |
| Requirements not validated | Built wrong thing | Requirements questionnaire first |

### 9.2 Mandatory Checks Before Deployment

- [ ] Requirements questionnaire completed
- [ ] Cost estimate approved by stakeholder
- [ ] Deployment scripts tested in dev environment
- [ ] Smoke test checklist prepared
- [ ] Rollback procedure documented

---

## 10. Appendices

### Appendix A: Resource Naming Convention

```
Pattern: {resource-type}-{project}-{environment}-{region}

Examples:
rg-tktph-avd-prod-sea       Resource Group
vnet-tktph-avd-sea          Virtual Network
snet-avd                    Subnet
nsg-tktph-avd               Network Security Group
vm-tktph-01                 Session Host 1
vm-tktph-02                 Session Host 2
st-tktphfslogix             Storage Account (FSLogix)
law-tktph-avd-sea           Log Analytics Workspace
```

### Appendix B: Deployment Checklist

See: `implementation-checklist.md`

### Appendix C: Validation Checklist

See: `validation-checklist.md`

---

**Document End**

*This architecture supersedes v1 and v2. All previous Windows Server-based designs are deprecated.*
