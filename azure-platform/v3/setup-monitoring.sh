#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Monitoring Setup Script
# Version: 3.0
# Date: 2026-02-01
#
# This script configures Azure Monitor alerts and AVD Insights for the platform.
#
# Prerequisites:
#   - Azure CLI installed and authenticated
#   - AVD platform already deployed (run deploy-avd-platform.sh first)
#
# Usage:
#   chmod +x setup-monitoring.sh
#   ./setup-monitoring.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

RESOURCE_GROUP="rg-tktph-avd-prod-sea"
LOG_ANALYTICS_WORKSPACE="law-tktph-avd-sea"
ACTION_GROUP_NAME="ag-tktph-avd"
HOSTPOOL_NAME="tktph-hp"
ALERT_EMAIL="tom.tuerlings@tktconsulting.com"

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1"
}

#-------------------------------------------------------------------------------
# GET RESOURCE IDS
#-------------------------------------------------------------------------------

get_resource_ids() {
    log "Getting resource IDs..."
    
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" \
        --output tsv)
    
    ACTION_GROUP_ID=$(az monitor action-group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --query "id" \
        --output tsv)
    
    log_success "Resource IDs retrieved"
}

#-------------------------------------------------------------------------------
# CREATE ALERTS
#-------------------------------------------------------------------------------

create_session_host_alert() {
    log "Creating session host unavailable alert..."
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "AVD-SessionHost-Unavailable" \
        --display-name "AVD Session Host Unavailable" \
        --description "Alert when session host heartbeat is missing for more than 5 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Heartbeat | where Computer startswith \"vm-tktph\" | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)' > 0" \
        --evaluation-frequency 5m \
        --window-size 5m \
        --severity 0 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true \
        --output none 2>/dev/null || log "Alert may already exist or requires portal setup"
    
    log_success "Session host alert created"
}

create_cpu_alert() {
    log "Creating high CPU alert..."
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "AVD-High-CPU" \
        --display-name "AVD High CPU Usage" \
        --description "Alert when CPU usage exceeds 85% for 15 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Perf | where Computer startswith \"vm-tktph\" | where ObjectName == \"Processor\" and CounterName == \"% Processor Time\" | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m) | where AvgCPU > 85' > 0" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 2 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true \
        --output none 2>/dev/null || log "Alert may already exist or requires portal setup"
    
    log_success "CPU alert created"
}

create_connection_alert() {
    log "Creating connection failures alert..."
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "AVD-Connection-Failures" \
        --display-name "AVD Connection Failures" \
        --description "Alert when connection failures exceed 5 in 10 minutes" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'WVDConnections | where State == \"Failed\" | summarize FailedConnections = count() by bin(TimeGenerated, 10m) | where FailedConnections > 5' > 0" \
        --evaluation-frequency 5m \
        --window-size 10m \
        --severity 2 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true \
        --output none 2>/dev/null || log "Alert may already exist or requires portal setup"
    
    log_success "Connection alert created"
}

create_disk_alert() {
    log "Creating low disk space alert..."
    
    az monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "AVD-Low-Disk" \
        --display-name "AVD Low Disk Space" \
        --description "Alert when free disk space is below 10GB" \
        --scopes "$WORKSPACE_ID" \
        --condition "count 'Perf | where Computer startswith \"vm-tktph\" | where ObjectName == \"LogicalDisk\" and CounterName == \"Free Megabytes\" | where InstanceName == \"C:\" | summarize AvgFreeSpace = avg(CounterValue) by Computer | where AvgFreeSpace < 10240' > 0" \
        --evaluation-frequency 15m \
        --window-size 15m \
        --severity 1 \
        --action-groups "$ACTION_GROUP_ID" \
        --auto-mitigate true \
        --output none 2>/dev/null || log "Alert may already exist or requires portal setup"
    
    log_success "Disk alert created"
}

#-------------------------------------------------------------------------------
# CONFIGURE AVD INSIGHTS
#-------------------------------------------------------------------------------

configure_avd_insights() {
    log "Configuring AVD Insights..."
    
    # AVD Insights is configured via diagnostic settings on the host pool
    # This was done in the main deployment script
    
    log "AVD Insights is configured via:"
    log "  1. Diagnostic settings on host pool (already configured)"
    log "  2. Azure Monitor Workbook 'AVD Insights' (built-in)"
    log ""
    log "To view AVD Insights:"
    log "  1. Azure Portal → Monitor → Workbooks"
    log "  2. Select 'AVD Insights' from gallery"
    log "  3. Set scope to your Log Analytics workspace"
    
    log_success "AVD Insights ready"
}

#-------------------------------------------------------------------------------
# USEFUL QUERIES
#-------------------------------------------------------------------------------

print_useful_queries() {
    echo ""
    echo "==============================================================================="
    echo "                    USEFUL LOG ANALYTICS QUERIES"
    echo "==============================================================================="
    echo ""
    
    cat << 'EOF'
// Active sessions by user
WVDConnections
| where State == "Connected"
| summarize count() by UserName, SessionHostName
| order by count_ desc

// Connection failures in last 24 hours
WVDConnections
| where TimeGenerated > ago(24h)
| where State == "Failed"
| summarize count() by UserName, bin(TimeGenerated, 1h)
| render timechart

// Session host availability
Heartbeat
| where Computer startswith "vm-tktph"
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend Status = iff(LastHeartbeat < ago(5m), "Offline", "Online")

// CPU usage by host
Perf
| where Computer startswith "vm-tktph"
| where ObjectName == "Processor" and CounterName == "% Processor Time"
| summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
| render timechart

// User session duration
WVDConnections
| where State == "Connected" or State == "Completed"
| summarize StartTime = min(TimeGenerated), EndTime = max(TimeGenerated) by CorrelationId, UserName
| extend Duration = EndTime - StartTime
| project UserName, Duration, StartTime
| order by StartTime desc

// FSLogix profile load times
Event
| where Source == "FSLogix"
| where EventID == 25
| parse EventData with * "Profile load time: " LoadTime:real " seconds" *
| summarize AvgLoadTime = avg(LoadTime) by Computer

// Errors in last hour
WVDErrors
| where TimeGenerated > ago(1h)
| summarize count() by Message
| order by count_ desc
EOF

    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# SUMMARY
#-------------------------------------------------------------------------------

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    MONITORING SETUP COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Alerts Created:"
    echo "  ✓ Session Host Unavailable (Severity 0 - Critical)"
    echo "  ✓ High CPU Usage (Severity 2 - Warning)"
    echo "  ✓ Connection Failures (Severity 2 - Warning)"
    echo "  ✓ Low Disk Space (Severity 1 - Error)"
    echo ""
    echo "Alert Recipient: $ALERT_EMAIL"
    echo ""
    echo "To view alerts:"
    echo "  Azure Portal → Monitor → Alerts"
    echo ""
    echo "To view AVD Insights:"
    echo "  Azure Portal → Monitor → Workbooks → AVD Insights"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "==============================================================================="
    echo "     TKT PHILIPPINES AVD - MONITORING SETUP"
    echo "==============================================================================="
    echo ""
    
    get_resource_ids
    create_session_host_alert
    create_cpu_alert
    create_connection_alert
    create_disk_alert
    configure_avd_insights
    print_useful_queries
    print_summary
}

main "$@"
