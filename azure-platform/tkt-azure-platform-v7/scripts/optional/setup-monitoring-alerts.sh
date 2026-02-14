#!/bin/bash
#===============================================================================
# TKT Philippines SAP Platform - Monitoring & Alerts Setup Script
# Version: 1.0
# Date: 2026-01-30
#
# This script configures Azure Monitor alerts for the platform.
#
# Usage:
#   chmod +x setup-monitoring-alerts.sh
#   ./setup-monitoring-alerts.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

CUSTOMER_NUMBER="001"
RESOURCE_GROUP="rg-customer-${CUSTOMER_NUMBER}-philippines"
LOCATION="southeastasia"

LOG_ANALYTICS_WORKSPACE="law-tkt-customer${CUSTOMER_NUMBER}-sea"

ACTION_GROUP_NAME="ag-customer-${CUSTOMER_NUMBER}-ph"
ACTION_GROUP_SHORT_NAME="cust${CUSTOMER_NUMBER}"
ALERT_EMAIL="tom.tuerlings@tktconsulting.com"

FIREWALL_NAME="afw-customer-${CUSTOMER_NUMBER}-ph"

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_action_group() {
    log "Creating action group..."
    
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "$ACTION_GROUP_SHORT_NAME" \
        --action email admin-email "$ALERT_EMAIL" \
        --tags Customer="Customer-${CUSTOMER_NUMBER}" Environment=Production
    
    log "Action group created."
}

get_action_group_id() {
    az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --query "id" \
        --output tsv
}

get_workspace_id() {
    az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" \
        --output tsv
}

create_vm_heartbeat_alert() {
    log "Creating VM heartbeat alert..."
    
    ACTION_GROUP_ID=$(get_action_group_id)
    WORKSPACE_ID=$(get_workspace_id)
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "VM-Heartbeat-Missing" \
        --display-name "VM Heartbeat Missing" \
        --description "Alert when VM heartbeat is missing for more than 5 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)' > 0" \
        --condition-query "Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)" \
        --evaluation-frequency 5m \
        --window-size 5m \
        --severity 0 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true
    
    log "VM heartbeat alert created."
}

create_high_cpu_alert() {
    log "Creating high CPU alert..."
    
    ACTION_GROUP_ID=$(get_action_group_id)
    WORKSPACE_ID=$(get_workspace_id)
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "VM-High-CPU" \
        --display-name "VM High CPU Usage" \
        --description "Alert when CPU usage exceeds 85% for 15 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Perf | where ObjectName == \"Processor\" and CounterName == \"% Processor Time\" | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgCPU > 85' > 0" \
        --condition-query "Perf | where ObjectName == \"Processor\" and CounterName == \"% Processor Time\" | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgCPU > 85" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 2 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true
    
    log "High CPU alert created."
}

create_low_disk_alert() {
    log "Creating low disk space alert..."
    
    ACTION_GROUP_ID=$(get_action_group_id)
    WORKSPACE_ID=$(get_workspace_id)
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "VM-Low-Disk" \
        --display-name "VM Low Disk Space" \
        --description "Alert when free disk space is below 10%" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Perf | where ObjectName == \"LogicalDisk\" and CounterName == \"% Free Space\" | where InstanceName == \"C:\" | summarize AvgFreeSpace = avg(CounterValue) by Computer | where AvgFreeSpace < 10' > 0" \
        --condition-query "Perf | where ObjectName == \"LogicalDisk\" and CounterName == \"% Free Space\" | where InstanceName == \"C:\" | summarize AvgFreeSpace = avg(CounterValue) by Computer | where AvgFreeSpace < 10" \
        --evaluation-frequency 15m \
        --window-size 15m \
        --severity 1 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true
    
    log "Low disk space alert created."
}

create_firewall_block_spike_alert() {
    log "Creating firewall block spike alert..."
    
    ACTION_GROUP_ID=$(get_action_group_id)
    WORKSPACE_ID=$(get_workspace_id)
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Firewall-Block-Spike" \
        --display-name "Azure Firewall Block Spike" \
        --description "Alert when more than 50 requests are blocked in 5 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'AzureDiagnostics | where Category == \"AzureFirewallApplicationRule\" | where msg_s contains \"Deny\" | summarize BlockCount = count() by bin(TimeGenerated, 5m) | where BlockCount > 50' > 0" \
        --condition-query "AzureDiagnostics | where Category == \"AzureFirewallApplicationRule\" | where msg_s contains \"Deny\" | summarize BlockCount = count() by bin(TimeGenerated, 5m) | where BlockCount > 50" \
        --evaluation-frequency 5m \
        --window-size 5m \
        --severity 2 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true
    
    log "Firewall block spike alert created."
}

create_failed_login_alert() {
    log "Creating failed login alert..."
    
    ACTION_GROUP_ID=$(get_action_group_id)
    WORKSPACE_ID=$(get_workspace_id)
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Failed-Login-Attempts" \
        --display-name "Multiple Failed Login Attempts" \
        --description "Alert when more than 5 failed login attempts in 10 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'SecurityEvent | where EventID == 4625 | summarize FailedLogins = count() by Computer, Account, bin(TimeGenerated, 10m) | where FailedLogins > 5' > 0" \
        --condition-query "SecurityEvent | where EventID == 4625 | summarize FailedLogins = count() by Computer, Account, bin(TimeGenerated, 10m) | where FailedLogins > 5" \
        --evaluation-frequency 5m \
        --window-size 10m \
        --severity 1 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true
    
    log "Failed login alert created."
}

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                MONITORING & ALERTS SETUP COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Action Group: $ACTION_GROUP_NAME"
    echo "Email Recipient: $ALERT_EMAIL"
    echo ""
    echo "Alerts Created:"
    echo "  ✓ VM Heartbeat Missing (Critical)"
    echo "  ✓ VM High CPU Usage (Warning)"
    echo "  ✓ VM Low Disk Space (Critical)"
    echo "  ✓ Firewall Block Spike (Warning)"
    echo "  ✓ Failed Login Attempts (Critical)"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    log "Starting monitoring and alerts setup for Customer $CUSTOMER_NUMBER"
    
    create_action_group
    create_vm_heartbeat_alert
    create_high_cpu_alert
    create_low_disk_alert
    create_firewall_block_spike_alert
    create_failed_login_alert
    print_summary
}

main "$@"
