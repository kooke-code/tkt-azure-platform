# TKT Philippines AVD Platform - Role Requirements

**Version:** 9.1 | **Date:** 2026-02-17

## Overview

V9.1 splits deployment into two tracks to support operators with different permission levels. This document details the exact roles required for each script.

## Role Matrix

### Track A — Identity (Global Admin)

| Script | Azure RBAC | Entra ID Directory Role | Microsoft Graph Permissions |
|--------|-----------|------------------------|-----------------------------|
| `deploy-identity.sh` | — | **User Administrator** (minimum) or Global Admin | User.ReadWrite.All, Group.ReadWrite.All, Device.ReadWrite.All |
| `deploy-conditional-access.sh` | — | **Conditional Access Administrator** (minimum) or Global Admin | Policy.ReadWrite.ConditionalAccess, Application.Read.All |
| `deploy-teams-team.sh` | — | **Teams Administrator** (minimum) or Global Admin | Team.Create, Group.ReadWrite.All, TeamMember.ReadWrite.All |
| `destroy-identity.sh` | — | **User Administrator** (minimum) or Global Admin | User.ReadWrite.All, Group.ReadWrite.All, Policy.ReadWrite.ConditionalAccess |

### Track B — Infrastructure (Contributor)

| Script | Azure RBAC | Entra ID Directory Role | Notes |
|--------|-----------|------------------------|-------|
| `deploy-infra.sh` | **Contributor** + **User Access Administrator** | — | UAA needed for RBAC role assignments |
| `deploy-azure-firewall.sh` | **Contributor** | — | Creates firewall, policies, routes |
| `destroy-infra.sh` | **Contributor** + **User Access Administrator** | — | UAA needed to remove role assignments/locks |

## Role Descriptions

### Azure RBAC Roles (Subscription Level)

| Role | Scope | What It Allows |
|------|-------|----------------|
| **Contributor** | Subscription | Create/manage all Azure resources (VMs, VNets, storage, etc.) but cannot manage access |
| **User Access Administrator** | Subscription | Assign RBAC roles to users/groups on Azure resources |

### Entra ID Directory Roles

| Role | What It Allows |
|------|----------------|
| **Global Administrator** | Full access to Entra ID and all Microsoft cloud services |
| **User Administrator** | Create/manage users and groups, reset passwords |
| **Conditional Access Administrator** | Create/manage Conditional Access policies |
| **Teams Administrator** | Manage Teams service, create teams, manage channels |
| **Cloud Device Administrator** | Manage device objects in Entra ID (for device cleanup) |

## Minimum Privilege Recommendations

### For Yannick (Track B Operator)

Yannick needs these Azure RBAC roles on the subscription:
- **Contributor** — for all resource creation
- **User Access Administrator** — for RBAC role assignments (Storage SMB roles, VM User Login, Desktop Virtualization User)

He does **not** need any Entra ID directory roles.

### For Config Admin (Track A Operator)

The Global Admin (`config@tktconsulting.be`) runs Track A scripts. If you want to minimize the use of Global Admin, you can create a service account with:
- **User Administrator** — for `deploy-identity.sh` and `destroy-identity.sh`
- **Conditional Access Administrator** — for `deploy-conditional-access.sh`
- **Teams Administrator** — for `deploy-teams-team.sh`
- **Cloud Device Administrator** — for device cleanup in `deploy-identity.sh`

However, using Global Admin is simpler and acceptable for a small deployment like this.

## Verification Commands

Check your current roles:

```bash
# Azure RBAC roles
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) \
    --query "[].{Role:roleDefinitionName, Scope:scope}" -o table

# Entra ID directory roles
az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/me/memberOf/microsoft.graph.directoryRole" \
    --query "value[].displayName" -o tsv
```

## Deployment Flow

```
Track A (Global Admin):                Track B (Contributor + UAA):

  deploy-identity.sh
      │
      ├── deploy-conditional-access.sh
      │
      ├── deploy-teams-team.sh
      │
      ├── Assign M365 F3 licenses
      │
      └── Hand off ─────────────────►  deploy-infra.sh
                                           │
                                           └── deploy-azure-firewall.sh
```

The security group Object ID output by `deploy-identity.sh` is the handoff point. `deploy-infra.sh` validates this group exists before proceeding.
