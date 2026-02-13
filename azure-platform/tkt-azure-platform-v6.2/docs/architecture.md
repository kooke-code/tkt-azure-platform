# TKT Philippines AVD Platform - Architecture Document

**Version:** 6.2  
**Date:** February 13, 2026  
**Classification:** Internal  
**Domain:** tktconsulting.be

---

## 1. Executive Summary

This document describes the Azure Virtual Desktop (AVD) platform architecture for TKT Consulting Philippines. The platform provides secure, cost-effective remote desktop access for SAP consultants serving European customers.

### Key Metrics

| Metric | Value |
|--------|-------|
| Monthly Cost | €235 |
| Deployment Time | ~20 minutes |
| Max Concurrent Users | 8 |
| Session Host Count | 2 |
| Join Type | Microsoft Entra ID (cloud-only) |

---

## 2. Architecture Overview

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AZURE CLOUD (Southeast Asia)                              │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │              Resource Group: rg-tktph-avd-prod-sea                         │ │
│  │                                                                            │ │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    Virtual Network: vnet-tktph-avd-sea              │  │ │
│  │  │                         10.2.0.0/16                                 │  │ │
│  │  │                                                                     │  │ │
│  │  │  ┌─────────────────────────────────────────────────────────────┐   │  │ │
│  │  │  │              Subnet: snet-avd (10.2.1.0/24)                 │   │  │ │
│  │  │  │                    NSG: nsg-tktph-avd                       │   │  │ │
│  │  │  │                                                             │   │  │ │
│  │  │  │   ┌─────────────┐          ┌─────────────┐                 │   │  │ │
│  │  │  │   │ vm-tktph-01 │          │ vm-tktph-02 │                 │   │  │ │
│  │  │  │   │  D4s_v3     │          │  D4s_v3     │                 │   │  │ │
│  │  │  │   │ 10.2.1.4    │          │ 10.2.1.5    │                 │   │  │ │
│  │  │  │   │ Entra Join  │          │ Entra Join  │                 │   │  │ │
│  │  │  │   └──────┬──────┘          └──────┬──────┘                 │   │  │ │
│  │  │  │          └────────────┬───────────┘                        │   │  │ │
│  │  │  └───────────────────────┼────────────────────────────────────┘   │  │ │
│  │  └──────────────────────────┼────────────────────────────────────────┘  │ │
│  │                             │                                           │ │
│  │  ┌──────────────────────────┴────────────────────────────────────────┐  │ │
│  │  │                    AVD Control Plane                              │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │  │ │
│  │  │  │  tktph-ws   │  │  tktph-hp   │  │      tktph-dag          │   │  │ │
│  │  │  │  Workspace  │──│  Host Pool  │──│  Desktop App Group      │   │  │ │
│  │  │  │             │  │  (Pooled)   │  │  (Users Assigned)       │   │  │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────────────────┘   │  │ │
│  │  └───────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                         │ │
│  │  ┌─────────────────────────────┐  ┌─────────────────────────────────┐  │ │
│  │  │   sttktphfslogix            │  │   law-tktph-avd-sea            │  │ │
│  │  │   Premium FileStorage       │  │   Log Analytics                │  │ │
│  │  │   FSLogix Profiles (100GB)  │  │   90-day retention             │  │ │
│  │  └─────────────────────────────┘  └─────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ HTTPS (443)
                                      ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                           AVD Gateway Service                                  │
│                  rdweb.wvd.microsoft.com (Microsoft-managed)                  │
└───────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│   Philippines Consultants    │    Belgium Administrators    │   Web Client    │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Summary

| Component | Name | Purpose |
|-----------|------|---------|
| Resource Group | rg-tktph-avd-prod-sea | Contains all resources |
| Virtual Network | vnet-tktph-avd-sea | Network isolation (10.2.0.0/16) |
| Subnet | snet-avd | Session hosts (10.2.1.0/24) |
| NSG | nsg-tktph-avd | Network security rules |
| Storage | sttktphfslogix | FSLogix profile storage |
| Log Analytics | law-tktph-avd-sea | Monitoring and diagnostics |
| Workspace | tktph-ws | AVD workspace |
| Host Pool | tktph-hp | Pooled session management |
| App Group | tktph-dag | Desktop application group |
| VMs | vm-tktph-01, vm-tktph-02 | Session hosts |

---

## 3. Identity Architecture (V6.2)

### 3.1 Entra ID Join Configuration

V6.2 uses **Microsoft Entra ID join** (cloud-only) instead of traditional AD domain join.

| Component | Configuration |
|-----------|---------------|
| VM Identity | System-assigned managed identity |
| Join Extension | AADLoginForWindows v2.0 |
| DSC Parameter | `aadJoin: true` |
| User RBAC | Virtual Machine User Login |

### 3.2 Authentication Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  User    │────▶│ Entra ID │────▶│   AVD    │────▶│ Session  │
│ Browser  │     │   MFA    │     │ Gateway  │     │  Host    │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
     │                │                │                │
     │  1. Login      │                │                │
     │───────────────▶│                │                │
     │                │                │                │
     │  2. MFA        │                │                │
     │◀──────────────▶│                │                │
     │                │                │                │
     │  3. Token      │  4. Connect    │                │
     │◀───────────────│───────────────▶│                │
     │                │                │                │
     │                │                │  5. Session    │
     │◀───────────────────────────────────────────────▶│
```

### 3.3 Required RBAC Roles

| Role | Scope | Purpose |
|------|-------|---------|
| Desktop Virtualization User | tktph-dag (App Group) | Access AVD workspace |
| Virtual Machine User Login | vm-tktph-01, vm-tktph-02 | Entra ID authentication to VMs |

### 3.4 Security Group

| Group | Members | Roles Assigned |
|-------|---------|----------------|
| TKT-Philippines-AVD-Users | ph-consultant-001 to 004 | Desktop Virtualization User, VM User Login |

---

## 4. Session Host Configuration

### 4.1 VM Specifications

| Setting | Value |
|---------|-------|
| VM Size | Standard_D4s_v3 |
| vCPUs | 4 |
| RAM | 16 GB |
| OS Disk | 128 GB Premium SSD |
| OS Image | Windows 11 Enterprise Multi-session 23H2 |
| License | Windows_Client (Azure Hybrid Benefit) |
| Identity | System-assigned managed identity |

### 4.2 VM Extensions

| Extension | Publisher | Purpose |
|-----------|-----------|---------|
| AADLoginForWindows | Microsoft.Azure.ActiveDirectory | Entra ID join |
| DSC | Microsoft.Powershell | AVD agent installation |
| AzureMonitorWindowsAgent | Microsoft.Azure.Monitor | Telemetry |

### 4.3 Host Pool Settings

| Setting | Value |
|---------|-------|
| Type | Pooled |
| Load Balancer | Breadth-first |
| Max Sessions per Host | 4 |
| Total Capacity | 8 concurrent users |

---

## 5. Storage Architecture

### 5.1 FSLogix Profile Storage

| Setting | Value |
|---------|-------|
| Storage Account | sttktphfslogix |
| Kind | FileStorage |
| SKU | Premium_LRS |
| Share Name | profiles |
| Quota | 100 GB |
| UNC Path | `\\sttktphfslogix.file.core.windows.net\profiles` |

### 5.2 Profile Settings

| Setting | Value |
|---------|-------|
| Container Type | VHD |
| Size Mode | Dynamic |
| Max Size per User | 30 GB |

---

## 6. Network Architecture

### 6.1 IP Addressing

| Component | Address |
|-----------|---------|
| Virtual Network | 10.2.0.0/16 |
| AVD Subnet | 10.2.1.0/24 |
| vm-tktph-01 | 10.2.1.4 |
| vm-tktph-02 | 10.2.1.5 |

### 6.2 Network Security

| Rule | Direction | Action |
|------|-----------|--------|
| AVD Service | Outbound | Allow (WindowsVirtualDesktop tag) |
| Azure Services | Outbound | Allow (AzureCloud tag) |
| Internet | Outbound | Allow (for updates) |
| Inbound | All | Deny (no public IPs) |

---

## 7. Monitoring

### 7.1 Log Analytics

| Setting | Value |
|---------|-------|
| Workspace | law-tktph-avd-sea |
| Retention | 90 days |
| SKU | PerGB2018 |

### 7.2 Alerts

| Alert | Condition | Action |
|-------|-----------|--------|
| VM Stopped | PowerState != Running | Email to admin |
| High CPU | > 90% for 5 min | Email to admin |
| Session Host Unavailable | Status != Available | Email to admin |

---

## 8. Cost Analysis

### 8.1 Monthly Breakdown

| Component | Cost |
|-----------|------|
| 2x D4s_v3 VMs | €190 |
| Premium Storage (100GB) | €20 |
| Log Analytics (~5GB) | €15 |
| Networking | €10 |
| **Total** | **€235** |

### 8.2 Cost per User

| Users | Cost/User |
|-------|-----------|
| 4 (minimum) | €59 |
| 8 (maximum) | €29 |

---

## 9. Disaster Recovery

### 9.1 Recovery Objectives

| Metric | Target |
|--------|--------|
| RTO | 4 hours |
| RPO | 24 hours |

### 9.2 Recovery Procedure

1. Run `deploy-avd-platform.sh` to recreate infrastructure
2. Restore FSLogix profiles from Azure Files snapshots
3. Verify session host registration
4. Test user connectivity

---

## Appendix A: Deployment Checklist

- [x] Resource group created
- [x] Virtual network and subnet configured
- [x] NSG attached with proper rules
- [x] Storage account created (Premium FileStorage)
- [x] FSLogix file share created
- [x] Log Analytics workspace created
- [x] AVD workspace created
- [x] Host pool created (Pooled)
- [x] Application group created and linked
- [x] Session hosts deployed with managed identity
- [x] AADLoginForWindows extension installed
- [x] AVD agent installed with aadJoin=true
- [x] Session hosts registered and Available
- [x] User accounts created
- [x] Security group created
- [x] Desktop Virtualization User role assigned
- [x] Virtual Machine User Login role assigned
- [ ] Conditional Access policies configured
- [ ] SAP GUI installed on session hosts

---

*Document Version: 6.2 | February 13, 2026*
