# TKT Philippines AVD Platform - Cost Optimization Guide
## Version 3.0 - Achieving 85% Cost Reduction

**Date:** February 1, 2026  
**Status:** Production Ready

---

## Executive Summary

The v3 AVD architecture achieves **85% cost reduction** compared to the v2 Windows Server deployment:

| Metric | v2 (Server VM) | v3 (AVD) | Savings |
|--------|----------------|----------|---------|
| Monthly Cost | €1,487 | €220 | €1,267 (85%) |
| Cost per User | €372 | €55 | €317 (85%) |
| Budget Status | 10× over budget | 63% under budget | ✓ |

---

## 1. Cost Breakdown Comparison

### 1.1 v2 Architecture Costs (Abandoned)

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| Azure Firewall | €912 | Overkill for 4 users |
| Windows Server VM (D4s_v3) | €380 | 24/7 running |
| Azure Bastion | €100 | Unnecessary with AVD |
| Recovery Services Vault | €60 | Complex backup |
| Log Analytics | €15 | Over-provisioned |
| Storage | €20 | - |
| **Total** | **€1,487** | **10× over budget** |

### 1.2 v3 Architecture Costs (Implemented)

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| Session Hosts (2× D4s_v5) | €110 | Business hours only |
| M365 Business Premium (4 users) | €80 | All-inclusive licensing |
| Azure Files Premium | €20 | FSLogix profiles |
| Log Analytics | €10 | Right-sized |
| Azure Firewall | €0 | Removed - NSG sufficient |
| Azure Bastion | €0 | Removed - AVD web client |
| Recovery Vault | €0 | OneDrive backup instead |
| **Total** | **€220** | **63% under budget** |

---

## 2. Key Cost Optimization Strategies

### 2.1 Remove Unnecessary Services

| Service Removed | Savings | Alternative |
|-----------------|---------|-------------|
| Azure Firewall | €912/month | NSG rules (free) |
| Azure Bastion | €100/month | AVD web client (free) |
| Recovery Services Vault | €60/month | OneDrive versioning (included) |

**Total savings from removal: €1,072/month**

### 2.2 Right-Size Compute

| Strategy | Before | After | Savings |
|----------|--------|-------|---------|
| VM running hours | 24/7 (720h) | Business hours (220h) | 69% |
| VM count | 1 large | 2 small (redundancy) | Optimized |
| OS | Windows Server | Windows 11 Multi-session | Included in M365 |

### 2.3 Auto-Shutdown Schedule

```
Schedule:
  Start:  08:00 PHT (00:00 UTC)
  Stop:   18:00 PHT (10:00 UTC)
  Days:   Monday - Friday
  
Calculation:
  Running hours:  10h × 22 days = 220 hours/month
  Always-on:      24h × 30 days = 720 hours/month
  Savings:        500 hours = 69% compute cost reduction
```

### 2.4 Inclusive Licensing

M365 Business Premium (€20/user/month) includes:
- Windows 11 Enterprise license (AVD rights)
- Office 365 apps
- OneDrive 1TB storage
- SharePoint team site
- Teams collaboration
- Microsoft Defender
- Entra ID P1

**Without M365, these would cost €50+/user/month separately**

---

## 3. Monthly Cost Model

### 3.1 Fixed Costs

| Component | Cost | Notes |
|-----------|------|-------|
| M365 Business Premium | €80 | 4 users × €20 |
| Azure Files Premium | €20 | 100GB quota |
| Log Analytics | €10 | ~5GB ingestion |
| **Subtotal** | **€110** | Does not scale with VM hours |

### 3.2 Variable Costs (Compute)

| Scenario | Hours | VM Cost | Total |
|----------|-------|---------|-------|
| Always-on (24/7) | 1,440 | €360 | €470 |
| Business hours | 440 | €110 | €220 |
| Minimal (testing) | 100 | €25 | €135 |
| Stopped | 0 | €0 | €110 |

### 3.3 Cost Formula

```
Monthly Cost = Fixed Costs + (VM Hours × VM Rate)
             = €110 + (Hours × €0.25)

Business Hours: €110 + (440 × €0.25) = €220
```

---

## 4. Scaling Economics

### 4.1 User Scaling

| Users | Session Hosts | M365 Licenses | Monthly Cost | Per User |
|-------|---------------|---------------|--------------|----------|
| 4 | 2× D4s_v5 | €80 | €220 | €55 |
| 8 | 2× D4s_v5 | €160 | €300 | €38 |
| 12 | 3× D4s_v5 | €240 | €405 | €34 |
| 20 | 4× D4s_v5 | €400 | €560 | €28 |

**Note:** Per-user cost decreases as fixed costs are spread across more users.

### 4.2 Customer Scaling (Multi-Tenant)

| Customers | Users | Shared Infra | Total Cost | Per Customer |
|-----------|-------|--------------|------------|--------------|
| 1 | 4 | N/A | €220 | €220 |
| 2 | 8 | Partial | €350 | €175 |
| 5 | 20 | Yes | €700 | €140 |
| 10 | 40 | Yes | €1,200 | €120 |

---

## 5. Reserved Instance Opportunities

### 5.1 Compute Reservations

| Term | Discount | D4s_v5 Price | Monthly Savings |
|------|----------|--------------|-----------------|
| Pay-as-you-go | 0% | €0.25/hour | Baseline |
| 1-year RI | 30% | €0.175/hour | €33/month |
| 3-year RI | 50% | €0.125/hour | €55/month |

### 5.2 When to Use Reserved Instances

| Scenario | Recommendation |
|----------|----------------|
| Pilot/testing | Pay-as-you-go |
| 1 customer confirmed | Pay-as-you-go |
| 3+ customers stable | 1-year RI |
| 5+ customers long-term | 3-year RI |

---

## 6. Cost Monitoring & Alerts

### 6.1 Budget Configuration

```bash
az consumption budget create \
  --budget-name "TKT-Philippines-AVD" \
  --resource-group "rg-tktph-avd-prod-sea" \
  --amount 300 \
  --category Cost \
  --time-grain Monthly
```

### 6.2 Alert Thresholds

| Threshold | Trigger | Action |
|-----------|---------|--------|
| 50% (€150) | Warning | Review usage |
| 75% (€225) | Alert | Investigate |
| 90% (€270) | Critical | Immediate review |
| 100% (€300) | Exceeded | Emergency action |

---

## 7. Comparison with Alternatives

### 7.1 AVD vs Windows 365

| Factor | AVD | Windows 365 |
|--------|-----|-------------|
| Model | Pooled shared | Dedicated per user |
| Cost (4× 4vCPU/16GB) | €220/month | €280/month |
| Flexibility | High | Low |
| Complexity | Medium | Low |

**Recommendation:** AVD for cost optimization; Windows 365 for simplicity.

---

## 8. Total Cost of Ownership (TCO)

### Three Year Comparison

| Item | AVD (v3) | Server VM (v2) |
|------|----------|----------------|
| Infrastructure | €7,920 | €53,532 |
| Setup (labor) | €500 | €1,000 |
| Management (labor) | €3,600 | €7,200 |
| **Total 3 Years** | **€12,020** | **€61,732** |
| **Savings** | | **€49,712 (80%)** |

---

## 9. Cost Optimization Checklist

### Monthly Tasks
- [ ] Review cost trends in Cost Management
- [ ] Check VM utilization (right-size if <30% average)
- [ ] Verify auto-shutdown compliance (100% expected)
- [ ] Compare actual vs budget

### Quarterly Tasks
- [ ] Evaluate Reserved Instance opportunity
- [ ] Review architecture for optimization
- [ ] Update cost projections

---

## Summary

The v3 AVD architecture achieves enterprise-grade remote desktop at SMB prices through:

1. **Right-sized security** - NSG instead of Azure Firewall (€912/month saved)
2. **Inclusive licensing** - M365 covers OS, apps, and backup
3. **Smart scheduling** - Pay only for business hours (69% compute savings)
4. **Modern architecture** - AVD instead of traditional VMs

**Result: 85% cost reduction while improving security and user experience.**

---

**Monthly cost target: €300 | Actual: €220 | Status: ✓ Under budget**
