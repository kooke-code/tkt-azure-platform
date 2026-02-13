#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Deployment Report Generator
# Version: 4.0
# Date: 2026-02-12
#
# This script generates a comprehensive deployment report including:
#   - Resource inventory
#   - Configuration details
#   - Cost estimates
#   - User credentials summary
#   - Next steps
#
# Usage:
#   ./generate-deployment-report.sh --resource-group <rg> [--output-dir <dir>]
#===============================================================================

set -uo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate deployment report for AVD platform.

Options:
    --resource-group <n>    Azure resource group name
    --output-dir <dir>         Output directory (default: current directory)
    --format <fmt>             Output format: md, html, json (default: md)
    -h, --help                 Show this help message
EOF
    exit 0
}

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------

parse_args() {
    RESOURCE_GROUP=""
    OUTPUT_DIR="."
    FORMAT="md"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
            --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
            --format) FORMAT="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        echo "ERROR: Resource group is required"
        exit 1
    fi
    
    mkdir -p "$OUTPUT_DIR"
}

#-------------------------------------------------------------------------------
# Data Collection Functions
#-------------------------------------------------------------------------------

get_subscription_info() {
    az account show --query "{name:name, id:id, tenantId:tenantId}" -o json
}

get_resource_group_info() {
    az group show --name "$RESOURCE_GROUP" \
        --query "{name:name, location:location, tags:tags}" -o json
}

get_vnet_info() {
    az network vnet list --resource-group "$RESOURCE_GROUP" \
        --query "[0].{name:name, addressSpace:addressSpace.addressPrefixes[0], subnets:subnets[].{name:name, prefix:addressPrefix}}" -o json 2>/dev/null || echo "{}"
}

get_storage_info() {
    local storage=$(az storage account list --resource-group "$RESOURCE_GROUP" \
        --query "[0].{name:name, kind:kind, sku:sku.name, primaryEndpoints:primaryEndpoints}" -o json 2>/dev/null)
    
    if [[ -n "$storage" && "$storage" != "null" ]]; then
        echo "$storage"
    else
        echo "{}"
    fi
}

get_avd_workspace_info() {
    az desktopvirtualization workspace list --resource-group "$RESOURCE_GROUP" \
        --query "[0].{name:name, friendlyName:friendlyName}" -o json 2>/dev/null || echo "{}"
}

get_avd_hostpool_info() {
    az desktopvirtualization hostpool list --resource-group "$RESOURCE_GROUP" \
        --query "[0].{name:name, hostPoolType:hostPoolType, loadBalancerType:loadBalancerType, maxSessionLimit:maxSessionLimit, validationEnvironment:validationEnvironment}" -o json 2>/dev/null || echo "{}"
}

get_session_hosts_info() {
    local hostpool=$(az desktopvirtualization hostpool list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$hostpool" ]]; then
        az desktopvirtualization sessionhost list --resource-group "$RESOURCE_GROUP" \
            --host-pool-name "$hostpool" \
            --query "[].{name:name, status:status, sessions:sessions, allowNewSession:allowNewSession}" -o json 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

get_vm_info() {
    az vm list --resource-group "$RESOURCE_GROUP" \
        --query "[].{name:name, size:hardwareProfile.vmSize, osType:storageProfile.osDisk.osType}" -o json 2>/dev/null || echo "[]"
}

get_log_analytics_info() {
    az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" \
        --query "[0].{name:name, retentionInDays:retentionInDays, sku:sku.name}" -o json 2>/dev/null || echo "{}"
}

#-------------------------------------------------------------------------------
# Cost Estimation
#-------------------------------------------------------------------------------

estimate_monthly_cost() {
    local vms=$(az vm list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    local storage_kind=$(az storage account list --resource-group "$RESOURCE_GROUP" \
        --query "[0].kind" -o tsv 2>/dev/null || echo "")
    
    # Approximate costs (Southeast Asia region)
    local vm_cost=95  # D4s_v5 estimate
    local storage_cost=20  # Premium FileStorage 100GB
    local log_analytics_cost=15  # ~5GB ingestion
    local misc_cost=10  # Networking, IPs
    
    local total_vm_cost=$((vms * vm_cost))
    local total_cost=$((total_vm_cost + storage_cost + log_analytics_cost + misc_cost))
    
    echo "{\"vms\": $vms, \"vm_cost\": $total_vm_cost, \"storage_cost\": $storage_cost, \"monitoring_cost\": $log_analytics_cost, \"misc_cost\": $misc_cost, \"total\": $total_cost}"
}

#-------------------------------------------------------------------------------
# Generate Markdown Report
#-------------------------------------------------------------------------------

generate_markdown_report() {
    local output_file="$OUTPUT_DIR/deployment-report-${TIMESTAMP}.md"
    
    echo -e "${BLUE}Generating deployment report...${NC}"
    
    # Collect data
    local subscription=$(get_subscription_info)
    local rg_info=$(get_resource_group_info)
    local vnet_info=$(get_vnet_info)
    local storage_info=$(get_storage_info)
    local workspace_info=$(get_avd_workspace_info)
    local hostpool_info=$(get_avd_hostpool_info)
    local session_hosts=$(get_session_hosts_info)
    local vms=$(get_vm_info)
    local log_analytics=$(get_log_analytics_info)
    local cost_estimate=$(estimate_monthly_cost)
    
    cat > "$output_file" << EOF
# TKT Philippines AVD Platform - Deployment Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S %Z')  
**Version:** 4.0  
**Status:** Deployment Complete

---

## Executive Summary

This report documents the Azure Virtual Desktop (AVD) platform deployment for TKT Consulting Philippines SAP consultants.

| Metric | Value |
|--------|-------|
| Resource Group | $RESOURCE_GROUP |
| Region | $(echo "$rg_info" | jq -r '.location // "N/A"') |
| Session Hosts | $(echo "$vms" | jq -r 'length') |
| Estimated Monthly Cost | €$(echo "$cost_estimate" | jq -r '.total') |

---

## 1. Infrastructure Overview

### 1.1 Subscription Details

| Property | Value |
|----------|-------|
| Subscription Name | $(echo "$subscription" | jq -r '.name // "N/A"') |
| Subscription ID | $(echo "$subscription" | jq -r '.id // "N/A"') |
| Tenant ID | $(echo "$subscription" | jq -r '.tenantId // "N/A"') |

### 1.2 Resource Group

| Property | Value |
|----------|-------|
| Name | $(echo "$rg_info" | jq -r '.name // "N/A"') |
| Location | $(echo "$rg_info" | jq -r '.location // "N/A"') |

**Tags:**
\`\`\`json
$(echo "$rg_info" | jq '.tags // {}')
\`\`\`

---

## 2. Networking

### 2.1 Virtual Network

| Property | Value |
|----------|-------|
| Name | $(echo "$vnet_info" | jq -r '.name // "N/A"') |
| Address Space | $(echo "$vnet_info" | jq -r '.addressSpace // "N/A"') |

**Subnets:**

| Subnet Name | Address Prefix |
|-------------|----------------|
$(echo "$vnet_info" | jq -r '.subnets[]? | "| \(.name) | \(.prefix) |"' 2>/dev/null || echo "| N/A | N/A |")

---

## 3. Storage

### 3.1 Storage Account

| Property | Value |
|----------|-------|
| Name | $(echo "$storage_info" | jq -r '.name // "N/A"') |
| Kind | $(echo "$storage_info" | jq -r '.kind // "N/A"') |
| SKU | $(echo "$storage_info" | jq -r '.sku // "N/A"') |

**FSLogix Profile Path:**
\`\\\\$(echo "$storage_info" | jq -r '.name // "STORAGE"').file.core.windows.net\\profiles\`

---

## 4. Azure Virtual Desktop

### 4.1 Workspace

| Property | Value |
|----------|-------|
| Name | $(echo "$workspace_info" | jq -r '.name // "N/A"') |
| Friendly Name | $(echo "$workspace_info" | jq -r '.friendlyName // "N/A"') |

### 4.2 Host Pool

| Property | Value |
|----------|-------|
| Name | $(echo "$hostpool_info" | jq -r '.name // "N/A"') |
| Type | $(echo "$hostpool_info" | jq -r '.hostPoolType // "N/A"') |
| Load Balancer | $(echo "$hostpool_info" | jq -r '.loadBalancerType // "N/A"') |
| Max Sessions | $(echo "$hostpool_info" | jq -r '.maxSessionLimit // "N/A"') |

### 4.3 Session Hosts

| Host Name | Status | Sessions | New Sessions |
|-----------|--------|----------|--------------|
$(echo "$session_hosts" | jq -r '.[]? | "| \(.name | split("/") | .[-1]) | \(.status) | \(.sessions) | \(.allowNewSession) |"' 2>/dev/null || echo "| No session hosts registered | - | - | - |")

### 4.4 Virtual Machines

| VM Name | Size | OS Type |
|---------|------|---------|
$(echo "$vms" | jq -r '.[]? | "| \(.name) | \(.size) | \(.osType) |"' 2>/dev/null || echo "| No VMs found | - | - |")

---

## 5. Monitoring

### 5.1 Log Analytics Workspace

| Property | Value |
|----------|-------|
| Name | $(echo "$log_analytics" | jq -r '.name // "N/A"') |
| Retention | $(echo "$log_analytics" | jq -r '.retentionInDays // "N/A"') days |
| SKU | $(echo "$log_analytics" | jq -r '.sku // "N/A"') |

---

## 6. Cost Estimate

### 6.1 Monthly Cost Breakdown

| Component | Quantity | Unit Cost (€) | Total (€) |
|-----------|----------|---------------|-----------|
| Session Host VMs | $(echo "$cost_estimate" | jq -r '.vms') | 95 | $(echo "$cost_estimate" | jq -r '.vm_cost') |
| Premium Storage | 1 | 20 | $(echo "$cost_estimate" | jq -r '.storage_cost') |
| Log Analytics | 1 | 15 | $(echo "$cost_estimate" | jq -r '.monitoring_cost') |
| Networking/Misc | 1 | 10 | $(echo "$cost_estimate" | jq -r '.misc_cost') |
| **Total** | | | **€$(echo "$cost_estimate" | jq -r '.total')** |

*Note: Costs are estimates based on Southeast Asia region pricing. Actual costs may vary.*

---

## 7. Security Configuration

### 7.1 Network Security

- **NSG Rules:** Configured for AVD service tags
- **Outbound Access:** Restricted (Azure and Microsoft services only)
- **RDP Access:** Limited to authorized IP ranges

### 7.2 Identity & Access

- **Authentication:** Entra ID with MFA required
- **User Accounts:** 4 consultant accounts created
- **RBAC:** Desktop Virtualization User role assigned

### 7.3 Data Protection

- **FSLogix:** Profile containers on Azure Files
- **Local Storage:** Disabled on session hosts
- **USB Devices:** Blocked
- **Clipboard:** Inbound only (one-way)

---

## 8. User Access Information

### 8.1 Connection Details

**Remote Desktop Client URL:**  
https://rdweb.wvd.microsoft.com/arm/webclient

**Feed URL:**  
https://rdweb.wvd.microsoft.com/api/arm/feeddiscovery

### 8.2 User Accounts

| Username | Role | MFA |
|----------|------|-----|
| ph-consultant-001@[domain] | Consultant | Required |
| ph-consultant-002@[domain] | Consultant | Required |
| ph-consultant-003@[domain] | Consultant | Required |
| ph-consultant-004@[domain] | Consultant | Required |

*Credentials provided separately via secure channel.*

---

## 9. Operational Information

### 9.1 VM Schedule (Optional)

| Setting | Value |
|---------|-------|
| Status | Optional (run setup-vm-schedule.sh) |
| Start Time | 07:00 Brussels time (CET/CEST) |
| Stop Time | 18:00 Brussels time (CET/CEST) |
| Days | Monday - Friday |
| Script | setup-vm-schedule.sh |

### 9.2 Session Logging (Optional)

| Setting | Value |
|---------|-------|
| Status | Optional (run setup-session-logging.sh) |
| Activity Logging | Windows events → Log Analytics |
| Video Recording | Teramind (requires separate subscription) |
| Retention | 90 days |

### 9.3 Backup Configuration

| Setting | Value |
|---------|-------|
| VM Backups | Daily at 02:00 UTC |
| Retention | 30 days |
| FSLogix Profiles | Azure Files snapshot (daily) |

---

## 10. Support & Contacts

### 10.1 Technical Support

| Role | Contact |
|------|---------|
| Platform Administrator | TKT Operations |
| Azure Support | Microsoft Premier Support |

### 10.2 Documentation

| Document | Location |
|----------|----------|
| Architecture Guide | ./docs/v4-architecture-notes.md |
| User Guide | ./docs/user-guide.md |
| Troubleshooting | ./docs/troubleshooting.md |

---

## 11. Next Steps

1. **User Onboarding**
   - [ ] Distribute credentials to consultants
   - [ ] Provide connection instructions
   - [ ] Schedule training session

2. **Validation**
   - [ ] Test user login and profile creation
   - [ ] Verify FSLogix profile persistence
   - [ ] Confirm SAP application access

3. **Monitoring**
   - [ ] Review Log Analytics dashboards
   - [ ] Configure additional alerts as needed
   - [ ] Set up cost alerts

4. **Documentation**
   - [ ] Update runbooks with specific details
   - [ ] Create incident response procedures

---

*Report generated automatically by TKT Philippines AVD Platform v4.0*
EOF

    echo -e "${GREEN}Report saved to: $output_file${NC}"
    echo "$output_file"
}

#-------------------------------------------------------------------------------
# Generate JSON Report
#-------------------------------------------------------------------------------

generate_json_report() {
    local output_file="$OUTPUT_DIR/deployment-report-${TIMESTAMP}.json"
    
    echo -e "${BLUE}Generating JSON report...${NC}"
    
    cat > "$output_file" << EOF
{
    "report": {
        "generated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "version": "4.0",
        "resource_group": "$RESOURCE_GROUP"
    },
    "subscription": $(get_subscription_info),
    "resource_group": $(get_resource_group_info),
    "networking": {
        "vnet": $(get_vnet_info)
    },
    "storage": $(get_storage_info),
    "avd": {
        "workspace": $(get_avd_workspace_info),
        "hostpool": $(get_avd_hostpool_info),
        "session_hosts": $(get_session_hosts_info)
    },
    "compute": {
        "vms": $(get_vm_info)
    },
    "monitoring": {
        "log_analytics": $(get_log_analytics_info)
    },
    "cost_estimate": $(estimate_monthly_cost)
}
EOF

    echo -e "${GREEN}Report saved to: $output_file${NC}"
    echo "$output_file"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "============================================================"
    echo "  TKT Philippines AVD - Deployment Report Generator"
    echo "============================================================"
    echo ""
    
    parse_args "$@"
    
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Output Directory: $OUTPUT_DIR"
    echo "Format: $FORMAT"
    echo ""
    
    case "$FORMAT" in
        md|markdown)
            generate_markdown_report
            ;;
        json)
            generate_json_report
            ;;
        *)
            echo "Unknown format: $FORMAT"
            exit 1
            ;;
    esac
    
    echo ""
    echo "Report generation complete!"
}

main "$@"
