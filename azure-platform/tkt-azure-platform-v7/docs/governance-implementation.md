# TKT Philippines AVD Platform - Governance Implementation
## Version 3.0 - Azure Virtual Desktop

**Date:** February 1, 2026  
**Status:** Production Ready

---

## 1. Governance Overview

### 1.1 Core Principles

| Principle | Implementation |
|-----------|----------------|
| **Cost Control** | Auto-shutdown, right-sizing, budget alerts |
| **Security by Default** | MFA required, no public IPs, NSG deny-all |
| **Audit Ready** | All actions logged, 30-day retention |
| **Least Privilege** | RBAC roles, Conditional Access |
| **Automation First** | IaC deployment, auto-remediation |

### 1.2 Governance Maturity (v3 vs v2)

| Area | v2 (Server VM) | v3 (AVD) | Improvement |
|------|----------------|----------|-------------|
| Cost Control | Over budget 10× | Under budget 63% | ✓ Resolved |
| Identity | Basic | MFA + Conditional Access | ✓ Enhanced |
| Network | Azure Firewall (overkill) | NSG (right-sized) | ✓ Optimized |
| Monitoring | Manual setup | AVD Insights built-in | ✓ Simplified |
| Backup | Complex vault | OneDrive auto-backup | ✓ Simplified |

---

## 2. Resource Organization

### 2.1 Naming Convention

```
Pattern: {resource-type}-{project}-{environment}-{region}

Resource Group:     rg-tktph-avd-prod-sea
Virtual Network:    vnet-tktph-avd-sea
Subnet:             snet-avd
NSG:                nsg-tktph-avd
Storage Account:    sttktphfslogix
Log Analytics:      law-tktph-avd-sea
AVD Workspace:      tktph-ws
Host Pool:          tktph-hp
Application Group:  tktph-dag
Session Hosts:      vm-tktph-01, vm-tktph-02
Action Group:       ag-tktph-avd
Automation Account: aa-tktph-avd
```

### 2.2 Tagging Strategy

| Tag | Value | Purpose |
|-----|-------|---------|
| Environment | Production | Lifecycle management |
| Project | TKT-Philippines | Cost allocation |
| Owner | tom.tuerlings@tktconsulting.com | Accountability |
| CostCenter | TKTPH-001 | Billing code |
| DataClassification | Confidential | Security level |
| AutoShutdown | Enabled | Cost control flag |
| CreatedBy | Automation | Audit trail |
| CreatedDate | 2026-02-01 | Audit trail |

### 2.3 Resource Group Structure

```
rg-tktph-avd-prod-sea/
├── Networking
│   ├── vnet-tktph-avd-sea
│   ├── snet-avd
│   └── nsg-tktph-avd
├── Compute
│   ├── vm-tktph-01
│   └── vm-tktph-02
├── Storage
│   └── sttktphfslogix
├── AVD Control Plane
│   ├── tktph-ws (Workspace)
│   ├── tktph-hp (Host Pool)
│   └── tktph-dag (Application Group)
├── Monitoring
│   ├── law-tktph-avd-sea
│   └── ag-tktph-avd
└── Automation
    └── aa-tktph-avd
```

---

## 3. Identity & Access Management

### 3.1 Security Groups

| Group | Purpose | Members |
|-------|---------|---------|
| TKT-Philippines-AVD-Users | AVD access | All consultants |
| TKT-Philippines-AVD-Admins | Full admin access | Platform owners |

### 3.2 Role Assignments

| Principal | Role | Scope | Purpose |
|-----------|------|-------|---------|
| AVD-Users | Desktop Virtualization User | Application Group | Access desktops |
| AVD-Users | Storage File Data SMB Contributor | Storage Account | Access FSLogix |
| AVD-Admins | Contributor | Resource Group | Manage resources |
| AVD-Admins | User Access Administrator | Resource Group | Manage access |
| Automation Account | Virtual Machine Contributor | Resource Group | Start/stop VMs |

### 3.3 Conditional Access Policies

#### Policy 1: Require MFA for AVD
```json
{
  "displayName": "Require MFA for AVD",
  "state": "enabled",
  "conditions": {
    "users": {
      "includeGroups": ["TKT-Philippines-AVD-Users"]
    },
    "applications": {
      "includeApplications": [
        "9cdead84-a844-4324-93f2-b2e6bb768d07",  // Windows Virtual Desktop
        "a4a365df-50f1-4397-bc59-1a1564b8bb9c"   // Windows Virtual Desktop Client
      ]
    }
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  }
}
```

#### Policy 2: Block Legacy Authentication
```json
{
  "displayName": "Block Legacy Auth",
  "state": "enabled",
  "conditions": {
    "users": {
      "includeUsers": ["All"]
    },
    "clientAppTypes": ["exchangeActiveSync", "other"]
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["block"]
  }
}
```

---

## 4. Cost Management

### 4.1 Budget Configuration

| Budget | Amount | Scope | Alerts |
|--------|--------|-------|--------|
| TKT-Philippines-Monthly | €300 | Resource Group | 50%, 75%, 90%, 100% |

### 4.2 Cost Optimization Measures

| Measure | Implementation | Savings |
|---------|----------------|---------|
| Auto-shutdown | Stop VMs 18:00-08:00 PHT | ~60% compute |
| Right-sized VMs | D4s_v5 instead of larger | Optimized |
| No Azure Firewall | NSG-only security | €912/month |
| No Bastion | AVD web client instead | €100/month |
| OneDrive backup | Instead of Recovery Vault | €60/month |

### 4.3 Budget Alerts Script

```bash
az consumption budget create \
  --budget-name "TKT-Philippines-Monthly" \
  --resource-group "rg-tktph-avd-prod-sea" \
  --amount 300 \
  --category Cost \
  --time-grain Monthly \
  --start-date "2026-02-01" \
  --end-date "2027-02-01" \
  --notifications "50"="{\"enabled\":true,\"operator\":\"GreaterThan\",\"threshold\":50,\"contactEmails\":[\"tom.tuerlings@tktconsulting.com\"]}" \
  --notifications "75"="{\"enabled\":true,\"operator\":\"GreaterThan\",\"threshold\":75,\"contactEmails\":[\"tom.tuerlings@tktconsulting.com\"]}" \
  --notifications "90"="{\"enabled\":true,\"operator\":\"GreaterThan\",\"threshold\":90,\"contactEmails\":[\"tom.tuerlings@tktconsulting.com\"]}"
```

---

## 5. Security Governance

### 5.1 Network Security

| Control | Implementation | Status |
|---------|----------------|--------|
| No public IPs | Session hosts have private IPs only | ✓ |
| NSG default deny | Deny all inbound by default | ✓ |
| Outbound filtering | Allow only required destinations | ✓ |
| Service endpoints | Storage service endpoint enabled | ✓ |

### 5.2 Data Protection

| Data Type | Protection | Backup |
|-----------|------------|--------|
| User files | OneDrive encryption | 93-day versioning |
| Team files | SharePoint encryption | 93-day retention |
| Profiles | Azure Files encryption | 7-day snapshots |
| Session hosts | Stateless - no data | N/A (redeploy) |

### 5.3 Security Monitoring

| Event Type | Log Location | Retention |
|------------|--------------|-----------|
| Sign-in logs | Entra ID | 30 days |
| AVD connections | Log Analytics | 30 days |
| NSG flow logs | Log Analytics | 30 days (optional) |
| Resource changes | Activity Log | 90 days |

---

## 6. Compliance Framework

### 6.1 GDPR Compliance

| Requirement | Implementation | Evidence |
|-------------|----------------|----------|
| Data minimization | No customer data on VMs | Architecture design |
| Encryption at rest | AES-256 all storage | Azure default |
| Encryption in transit | TLS 1.2+ required | NSG + storage config |
| Access control | Entra ID + MFA | Conditional Access |
| Audit trail | All connections logged | Log Analytics |
| Right to erasure | User profile deletion | FSLogix management |

### 6.2 Compliance Evidence Collection

```kusto
// User login audit
SigninLogs
| where TimeGenerated > ago(30d)
| where AppDisplayName == "Windows Virtual Desktop"
| project TimeGenerated, UserPrincipalName, IPAddress, Status

// Resource changes audit
AzureActivity
| where TimeGenerated > ago(30d)
| where ResourceGroup == "rg-tktph-avd-prod-sea"
| project TimeGenerated, Caller, OperationName, ActivityStatus
```

### 6.3 Audit Checklist

| Item | Frequency | Owner |
|------|-----------|-------|
| Review user access | Monthly | Admin |
| Review cost vs budget | Weekly | Admin |
| Review security alerts | Daily | Admin |
| Test backup recovery | Quarterly | Admin |
| Update documentation | On change | Admin |

---

## 7. Operational Governance

### 7.1 Change Management

| Change Type | Approval | Testing |
|-------------|----------|---------|
| User add/remove | Admin | N/A |
| VM scaling | Admin | Test subscription |
| Security policy | Admin + Review | Test environment |
| Major architecture | Stakeholder | Full validation |

### 7.2 Incident Response

| Severity | Response Time | Escalation |
|----------|---------------|------------|
| Critical (outage) | 30 minutes | Immediate |
| High (degraded) | 2 hours | Same day |
| Medium (issues) | 4 hours | Next day |
| Low (questions) | 24 hours | As needed |

### 7.3 Maintenance Windows

| Activity | Schedule | Duration | Notice |
|----------|----------|----------|--------|
| Windows Updates | Monthly | 2 hours | 48 hours |
| AVD Agent Updates | Automatic | N/A | N/A |
| FSLogix Updates | Quarterly | 1 hour | 1 week |

---

## 8. Automation & Self-Service

### 8.1 Automated Processes

| Process | Trigger | Action |
|---------|---------|--------|
| VM start | User connection attempt | Auto-start VM |
| VM stop | 18:00 PHT | Deallocate VMs |
| Alert | Threshold exceeded | Email notification |
| Backup | Daily 02:00 UTC | Azure Files snapshot |

### 8.2 Self-Service Capabilities

| Action | User Can Do | Admin Must Do |
|--------|-------------|---------------|
| Reset password | Yes (SSPR) | N/A |
| Connect to AVD | Yes | N/A |
| Change MFA method | Yes | N/A |
| Request access | No | Approve request |
| Install software | No | Deploy via image |

---

## 9. Documentation Requirements

### 9.1 Required Documentation

| Document | Location | Update Frequency |
|----------|----------|------------------|
| Architecture diagram | Git repo | On change |
| Runbooks | Git repo | On change |
| User guide | SharePoint | Quarterly |
| Incident log | Log Analytics | Continuous |
| Cost reports | Cost Management | Monthly |

### 9.2 Documentation Standards

- All changes must be documented in Git
- Architecture changes require updated diagrams
- Runbooks must include rollback procedures
- User guides must be accessible to end users

---

## 10. Governance Review Schedule

| Review | Frequency | Participants | Output |
|--------|-----------|--------------|--------|
| Cost review | Weekly | Admin | Adjustment if needed |
| Security review | Monthly | Admin + Security | Remediation plan |
| Compliance review | Quarterly | Admin + Compliance | Audit report |
| Architecture review | Annually | Stakeholders | Roadmap update |

---

## Appendix: Quick Reference

### Essential Commands

```bash
# Check resource group cost
az consumption usage list --scope "/subscriptions/{sub}/resourceGroups/rg-tktph-avd-prod-sea" --query "[].{Service:serviceName,Cost:pretaxCost}"

# List all users with AVD access
az ad group member list --group "TKT-Philippines-AVD-Users" --query "[].userPrincipalName"

# Check session host status
az desktopvirtualization sessionhost list --resource-group rg-tktph-avd-prod-sea --host-pool-name tktph-hp --query "[].{Name:name,Status:status}"

# Check active sessions
az desktopvirtualization usersession list --resource-group rg-tktph-avd-prod-sea --host-pool-name tktph-hp
```

### Emergency Contacts

| Role | Contact | Responsibility |
|------|---------|----------------|
| Platform Owner | tom.tuerlings@tktconsulting.com | All decisions |
| Azure Support | Microsoft Premier | P1 incidents |

---

**Document End**

*This governance framework ensures the TKT Philippines AVD platform operates securely, cost-effectively, and in compliance with requirements.*
