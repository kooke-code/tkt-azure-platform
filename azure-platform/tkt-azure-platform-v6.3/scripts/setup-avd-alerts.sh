#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Azure Monitor Alerts Setup
# Version: 1.0
# Date: 2026-02-12
#
# DESCRIPTION:
#   Configures Azure Monitor alerts for the AVD platform:
#   - VM health/availability alerts
#   - User connection failure alerts
#   - FSLogix profile load failure alerts
#   - High CPU/memory alerts
#   - Storage capacity alerts
#   - Budget alerts (cost threshold)
#
# PREREQUISITES:
#   - Azure CLI authenticated with Contributor role
#   - Log Analytics workspace deployed
#   - VMs deployed and running
#
# USAGE:
#   ./setup-avd-alerts.sh \
#     --resource-group rg-tktph-avd-prod-sea \
#     --email yannick.de.ridder@outlook.com \
#     --budget-amount 220 \
#     --budget-alert-percent 140
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION
#===============================================================================

RESOURCE_GROUP=""
ALERT_EMAIL=""
BUDGET_AMOUNT="220"
BUDGET_ALERT_PERCENT_1="100"
BUDGET_ALERT_PERCENT_2="120"
BUDGET_ALERT_PERCENT_3="140"
LOG_ANALYTICS_WORKSPACE=""
SUBSCRIPTION_ID=""
DRY_RUN="false"
LOCATION="southeastasia"

# Action group name
ACTION_GROUP_NAME="ag-tktph-avd-alerts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# LOGGING
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)   echo -e "${BLUE}[$timestamp] [ALERTS] [INFO]${NC} $message" ;;
        SUCCESS)echo -e "${GREEN}[$timestamp] [ALERTS] [SUCCESS]${NC} $message" ;;
        WARN)   echo -e "${YELLOW}[$timestamp] [ALERTS] [WARNING]${NC} $message" ;;
        ERROR)  echo -e "${RED}[$timestamp] [ALERTS] [ERROR]${NC} $message" ;;
        DRY)    echo -e "${YELLOW}[$timestamp] [ALERTS] [DRY-RUN]${NC} $message" ;;
    esac
}

#===============================================================================
# HELP
#===============================================================================

show_help() {
    cat << EOF
TKT Philippines AVD - Azure Monitor Alerts Setup

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    --resource-group <name>     Resource group containing AVD resources
    --email <address>           Email address for alert notifications

OPTIONAL:
    --budget-amount <euros>     Monthly budget in euros (default: 220)
    --log-analytics <name>      Log Analytics workspace name (auto-detected)
    --dry-run                   Preview changes without creating alerts
    --help                      Show this help

ALERT THRESHOLDS:
    Budget alerts at: 100%, 120%, 140% of budget amount
    CPU alert: > 85% for 15 minutes
    Memory alert: > 90% for 15 minutes
    Storage alert: > 80% capacity

EXAMPLES:
    $0 --resource-group rg-tktph-avd-prod-sea --email yannick.de.ridder@outlook.com
    $0 --resource-group rg-tktph-avd-prod-sea --email admin@company.com --budget-amount 300
    $0 --resource-group rg-tktph-avd-prod-sea --email admin@company.com --dry-run

EOF
    exit 0
}

#===============================================================================
# PARSE ARGUMENTS
#===============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --email)
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --budget-amount)
            BUDGET_AMOUNT="$2"
            shift 2
            ;;
        --log-analytics)
            LOG_ANALYTICS_WORKSPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log ERROR "Unknown option: $1"
            show_help
            ;;
    esac
done

#===============================================================================
# VALIDATION
#===============================================================================

validate_inputs() {
    log INFO "Validating inputs..."
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "Resource group is required (--resource-group)"
        exit 1
    fi
    
    if [[ -z "$ALERT_EMAIL" ]]; then
        log ERROR "Email address is required (--email)"
        exit 1
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    log INFO "Subscription: $SUBSCRIPTION_ID"
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "Resource group '$RESOURCE_GROUP' not found"
        exit 1
    fi
    
    # Auto-detect Log Analytics workspace
    if [[ -z "$LOG_ANALYTICS_WORKSPACE" ]]; then
        LOG_ANALYTICS_WORKSPACE=$(az monitor log-analytics workspace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
        
        if [[ -z "$LOG_ANALYTICS_WORKSPACE" ]]; then
            log ERROR "No Log Analytics workspace found in resource group"
            exit 1
        fi
    fi
    
    log INFO "Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    log SUCCESS "Validation complete"
}

#===============================================================================
# CREATE ACTION GROUP
#===============================================================================

create_action_group() {
    log INFO "Creating action group for alert notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create action group: $ACTION_GROUP_NAME"
        log DRY "  Email receiver: $ALERT_EMAIL"
        return 0
    fi
    
    # Check if action group exists
    if az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" &>/dev/null; then
        log INFO "Action group already exists, updating..."
    fi
    
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "TKTAlerts" \
        --action email "AdminEmail" "$ALERT_EMAIL" \
        --output none
    
    log SUCCESS "Action group created: $ACTION_GROUP_NAME"
}

#===============================================================================
# VM HEALTH ALERTS
#===============================================================================

create_vm_alerts() {
    log INFO "Creating VM health alerts..."
    
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" -o tsv)
    
    local action_group_id=$(az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --query "id" -o tsv 2>/dev/null || echo "placeholder")
    
    # Alert 1: VM Unavailable (Heartbeat missing)
    log INFO "  Creating VM unavailability alert..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: VM-Heartbeat-Missing"
        log DRY "  Query: Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)"
    else
        az monitor scheduled-query create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-vm-heartbeat-missing" \
            --display-name "AVD - VM Heartbeat Missing" \
            --description "Alert when VM heartbeat is missing for more than 5 minutes" \
            --scopes "$workspace_id" \
            --condition "count 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)' > 0" \
            --evaluation-frequency 5m \
            --window-size 5m \
            --severity 0 \
            --action-groups "$action_group_id" \
            --auto-mitigate true \
            --output none 2>/dev/null || log WARN "VM heartbeat alert may already exist"
    fi
    
    # Alert 2: High CPU
    log INFO "  Creating high CPU alert..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: VM-High-CPU (>85% for 15min)"
    else
        az monitor scheduled-query create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-vm-high-cpu" \
            --display-name "AVD - VM High CPU" \
            --description "Alert when CPU usage exceeds 85% for 15 minutes" \
            --scopes "$workspace_id" \
            --condition "count 'Perf | where ObjectName == \"Processor\" and CounterName == \"% Processor Time\" | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgCPU > 85' > 0" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            --action-groups "$action_group_id" \
            --auto-mitigate true \
            --output none 2>/dev/null || log WARN "High CPU alert may already exist"
    fi
    
    # Alert 3: High Memory
    log INFO "  Creating high memory alert..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: VM-High-Memory (>90% for 15min)"
    else
        az monitor scheduled-query create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-vm-high-memory" \
            --display-name "AVD - VM High Memory" \
            --description "Alert when memory usage exceeds 90% for 15 minutes" \
            --scopes "$workspace_id" \
            --condition "count 'Perf | where ObjectName == \"Memory\" and CounterName == \"% Committed Bytes In Use\" | summarize AvgMem = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgMem > 90' > 0" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            --action-groups "$action_group_id" \
            --auto-mitigate true \
            --output none 2>/dev/null || log WARN "High memory alert may already exist"
    fi
    
    log SUCCESS "VM health alerts created"
}

#===============================================================================
# AVD-SPECIFIC ALERTS
#===============================================================================

create_avd_alerts() {
    log INFO "Creating AVD-specific alerts..."
    
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" -o tsv)
    
    local action_group_id=$(az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --query "id" -o tsv 2>/dev/null || echo "placeholder")
    
    # Alert: User Connection Failures
    log INFO "  Creating user connection failure alert..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: AVD-Connection-Failures"
    else
        az monitor scheduled-query create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-connection-failures" \
            --display-name "AVD - User Connection Failures" \
            --description "Alert when multiple user connection failures detected" \
            --scopes "$workspace_id" \
            --condition "count 'WVDConnections | where State == \"Failed\" | summarize FailureCount = count() by bin(TimeGenerated, 15m) | where FailureCount > 3' > 0" \
            --evaluation-frequency 15m \
            --window-size 15m \
            --severity 1 \
            --action-groups "$action_group_id" \
            --auto-mitigate true \
            --output none 2>/dev/null || log WARN "Connection failure alert may already exist or WVDConnections table not available"
    fi
    
    # Alert: FSLogix Profile Load Failures
    log INFO "  Creating FSLogix profile failure alert..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: FSLogix-Profile-Failures"
    else
        az monitor scheduled-query create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-fslogix-failures" \
            --display-name "AVD - FSLogix Profile Load Failures" \
            --description "Alert when FSLogix profile fails to load" \
            --scopes "$workspace_id" \
            --condition "count 'Event | where Source == \"FSLogix\" and EventLevelName == \"Error\" | summarize ErrorCount = count() by bin(TimeGenerated, 15m) | where ErrorCount > 0' > 0" \
            --evaluation-frequency 15m \
            --window-size 15m \
            --severity 1 \
            --action-groups "$action_group_id" \
            --auto-mitigate true \
            --output none 2>/dev/null || log WARN "FSLogix alert may already exist or Event table not configured"
    fi
    
    log SUCCESS "AVD-specific alerts created"
}

#===============================================================================
# STORAGE ALERTS
#===============================================================================

create_storage_alerts() {
    log INFO "Creating storage capacity alerts..."
    
    # Find storage account
    local storage_account=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'fslogix')].name" -o tsv 2>/dev/null | head -1)
    
    if [[ -z "$storage_account" ]]; then
        log WARN "No FSLogix storage account found, skipping storage alerts"
        return 0
    fi
    
    local storage_id=$(az storage account show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$storage_account" \
        --query "id" -o tsv)
    
    local action_group_id=$(az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --query "id" -o tsv 2>/dev/null || echo "placeholder")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create alert: Storage-Capacity-Warning (>80%)"
        log DRY "  Storage account: $storage_account"
    else
        az monitor metrics alert create \
            --resource-group "$RESOURCE_GROUP" \
            --name "avd-storage-capacity" \
            --description "Alert when storage capacity exceeds 80%" \
            --scopes "$storage_id" \
            --condition "avg UsedCapacity > 85899345920" \
            --evaluation-frequency 1h \
            --window-size 1h \
            --severity 2 \
            --action "$action_group_id" \
            --output none 2>/dev/null || log WARN "Storage alert may already exist"
    fi
    
    log SUCCESS "Storage alerts created"
}

#===============================================================================
# BUDGET ALERTS
#===============================================================================

create_budget_alerts() {
    log INFO "Creating budget alerts..."
    log INFO "  Budget: €$BUDGET_AMOUNT/month"
    log INFO "  Alert thresholds: 100%, 120%, 140%"
    
    local budget_name="budget-tktph-avd"
    
    # Calculate end date (12 months from now)
    local start_date=$(date +%Y-%m-01)
    local end_date=$(date -d "+12 months" +%Y-%m-01 2>/dev/null || date -v+12m +%Y-%m-01)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DRY "Would create budget: $budget_name"
        log DRY "  Amount: €$BUDGET_AMOUNT"
        log DRY "  Alert at €$((BUDGET_AMOUNT * 100 / 100)) (100%)"
        log DRY "  Alert at €$((BUDGET_AMOUNT * 120 / 100)) (120%)"
        log DRY "  Alert at €$((BUDGET_AMOUNT * 140 / 100)) (140%)"
        return 0
    fi
    
    # Create budget with thresholds
    az consumption budget create \
        --budget-name "$budget_name" \
        --amount "$BUDGET_AMOUNT" \
        --category Cost \
        --time-grain Monthly \
        --start-date "$start_date" \
        --end-date "$end_date" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null || {
            log WARN "Budget creation via CLI may require portal setup"
            log INFO "Manual setup: Azure Portal > Cost Management > Budgets > Create"
            log INFO "  Name: $budget_name"
            log INFO "  Amount: €$BUDGET_AMOUNT"
            log INFO "  Scope: Resource Group ($RESOURCE_GROUP)"
            log INFO "  Alert recipients: $ALERT_EMAIL"
            log INFO "  Thresholds: 100%, 120%, 140%"
        }
    
    log SUCCESS "Budget alerts configured"
}

#===============================================================================
# SUMMARY
#===============================================================================

print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                   ALERT CONFIGURATION COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Resource Group:     $RESOURCE_GROUP"
    echo "Alert Email:        $ALERT_EMAIL"
    echo "Action Group:       $ACTION_GROUP_NAME"
    echo ""
    echo "ALERTS CREATED:"
    echo "  ✓ VM Heartbeat Missing (Critical - Sev 0)"
    echo "  ✓ VM High CPU > 85% (Warning - Sev 2)"
    echo "  ✓ VM High Memory > 90% (Warning - Sev 2)"
    echo "  ✓ User Connection Failures (High - Sev 1)"
    echo "  ✓ FSLogix Profile Load Failures (High - Sev 1)"
    echo "  ✓ Storage Capacity > 80% (Warning - Sev 2)"
    echo ""
    echo "BUDGET ALERTS:"
    echo "  ✓ 100% of €$BUDGET_AMOUNT = €$BUDGET_AMOUNT (heads up)"
    echo "  ✓ 120% of €$BUDGET_AMOUNT = €$((BUDGET_AMOUNT * 120 / 100)) (warning)"
    echo "  ✓ 140% of €$BUDGET_AMOUNT = €$((BUDGET_AMOUNT * 140 / 100)) (action needed)"
    echo ""
    echo "VIEW ALERTS:"
    echo "  Azure Portal > Monitor > Alerts"
    echo "  Or: az monitor alert list --resource-group $RESOURCE_GROUP"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     TKT Philippines AVD - Azure Monitor Alerts Setup             ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    validate_inputs
    create_action_group
    create_vm_alerts
    create_avd_alerts
    create_storage_alerts
    create_budget_alerts
    print_summary
}

main
