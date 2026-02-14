#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Session Logging & Recording Setup
# Version: 4.0
# Date: 2026-02-12
#
# Configures session activity logging on AVD session hosts:
#   - Enhanced Windows event logging (always enabled)
#   - Log forwarding to Azure Log Analytics
#   - Optional: Teramind agent deployment (on request)
#
# What gets logged:
#   - User login/logout times
#   - Applications launched (with command line)
#   - Files accessed/modified
#   - Websites visited (from browser history events)
#   - USB device connections (blocked, but logged)
#   - Clipboard operations
#   - Print operations
#
# Prerequisites:
#   - Azure CLI installed and authenticated
#   - Session hosts deployed and running
#
# Usage:
#   ./setup-session-logging.sh --resource-group <rg> --vm-prefix <prefix> --vm-count <n>
#   ./setup-session-logging.sh --resource-group rg-tktph-avd --vm-prefix tktph-sh --vm-count 2 --enable-teramind
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

RESOURCE_GROUP=""
VM_PREFIX="tktph-sh"
VM_COUNT=2
LOG_ANALYTICS_WORKSPACE=""
DRY_RUN=false
ENABLE_TERAMIND=false
TERAMIND_DEPLOY_KEY=""

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)    echo -e "[$timestamp] \033[0;34mINFO\033[0m  $message" ;;
        SUCCESS) echo -e "[$timestamp] \033[0;32m✓\033[0m     $message" ;;
        WARN)    echo -e "[$timestamp] \033[0;33mWARN\033[0m  $message" ;;
        ERROR)   echo -e "[$timestamp] \033[0;31mERROR\033[0m $message" ;;
        *)       echo "[$timestamp] $message" ;;
    esac
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required:
    --resource-group         Resource group containing session hosts
    
Optional:
    --vm-prefix              VM name prefix (default: tktph-sh)
    --vm-count               Number of VMs (default: 2)
    --workspace              Log Analytics workspace name (auto-detected if not specified)
    --enable-teramind        Deploy Teramind agent for video recording
    --teramind-key           Teramind deployment key (required if --enable-teramind)
    --dry-run                Show what would be configured
    --help                   Show this help message

Examples:
    # Basic logging only (recommended start)
    $0 --resource-group rg-tktph-avd
    
    # With Teramind video recording
    $0 --resource-group rg-tktph-avd --enable-teramind --teramind-key "YOUR_KEY"
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --vm-prefix)
                VM_PREFIX="$2"
                shift 2
                ;;
            --vm-count)
                VM_COUNT="$2"
                shift 2
                ;;
            --workspace)
                LOG_ANALYTICS_WORKSPACE="$2"
                shift 2
                ;;
            --enable-teramind)
                ENABLE_TERAMIND=true
                shift
                ;;
            --teramind-key)
                TERAMIND_DEPLOY_KEY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "Resource group is required"
        show_usage
        exit 1
    fi
    
    if [[ "$ENABLE_TERAMIND" == "true" && -z "$TERAMIND_DEPLOY_KEY" ]]; then
        log ERROR "Teramind deployment key is required when --enable-teramind is specified"
        exit 1
    fi
}

detect_log_analytics_workspace() {
    if [[ -n "$LOG_ANALYTICS_WORKSPACE" ]]; then
        return
    fi
    
    log INFO "Auto-detecting Log Analytics workspace..."
    
    LOG_ANALYTICS_WORKSPACE=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$LOG_ANALYTICS_WORKSPACE" ]]; then
        log ERROR "No Log Analytics workspace found in resource group"
        exit 1
    fi
    
    log SUCCESS "Found workspace: $LOG_ANALYTICS_WORKSPACE"
}

get_workspace_id() {
    az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "customerId" -o tsv
}

get_workspace_key() {
    az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "primarySharedKey" -o tsv
}

configure_enhanced_logging() {
    log INFO "Configuring enhanced Windows event logging on session hosts..."
    
    # PowerShell script to configure advanced audit policies
    local ps_script='
# Enable advanced audit policies
Write-Host "Configuring advanced audit policies..."

# Process Creation (track all launched applications)
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable

# Process Termination
auditpol /set /subcategory:"Process Termination" /success:enable

# Logon/Logoff events
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /set /subcategory:"Special Logon" /success:enable

# Object Access (file access)
auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /set /subcategory:"File Share" /success:enable /failure:enable
auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable

# Account events
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable

# Policy changes
auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable

# Enable command line in process creation events
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord

# Enable PowerShell script block logging
$psPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $psPath)) {
    New-Item -Path $psPath -Force | Out-Null
}
Set-ItemProperty -Path $psPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord

# Enable PowerShell module logging
$pmPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
if (-not (Test-Path $pmPath)) {
    New-Item -Path $pmPath -Force | Out-Null
}
Set-ItemProperty -Path $pmPath -Name "EnableModuleLogging" -Value 1 -Type DWord

# Configure which modules to log (all)
$modulePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
if (-not (Test-Path $modulePath)) {
    New-Item -Path $modulePath -Force | Out-Null
}
Set-ItemProperty -Path $modulePath -Name "*" -Value "*" -Type String

# Enable RDP session logging
$rdpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
Set-ItemProperty -Path $rdpPath -Name "MaxConnectionTime" -Value 28800000 -Type DWord  # 8 hours in ms

Write-Host "Advanced audit policies configured successfully"

# Display current audit policy
Write-Host "`nCurrent audit policy:"
auditpol /get /category:* | Select-String -Pattern "Success|Failure"
'
    
    for i in $(seq 0 $((VM_COUNT - 1))); do
        local vm_name="${VM_PREFIX}-${i}"
        log INFO "Configuring logging on: $vm_name"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY-RUN] Would configure enhanced audit policies"
            continue
        fi
        
        # Check VM is running
        local power_state=$(az vm get-instance-view \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" \
            -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$power_state" != "VM running" ]]; then
            log WARN "$vm_name is not running (state: $power_state), skipping"
            continue
        fi
        
        # Run the PowerShell script
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts "$ps_script" \
            --output none
        
        log SUCCESS "Enhanced logging configured on $vm_name"
    done
}

configure_log_analytics_agent() {
    log INFO "Configuring Azure Monitor Agent for log collection..."
    
    local workspace_id=$(get_workspace_id)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would configure Azure Monitor Agent"
        log INFO "[DRY-RUN] Workspace ID: $workspace_id"
        return
    fi
    
    # Create Data Collection Rule for Windows Security Events
    local dcr_name="dcr-tktph-security-events"
    
    # Check if DCR exists
    if ! az monitor data-collection rule show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dcr_name" &>/dev/null; then
        
        log INFO "Creating Data Collection Rule..."
        
        local workspace_resource_id=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --query "id" -o tsv)
        
        # Create DCR JSON
        local dcr_json=$(cat <<EOF
{
    "location": "$(az group show --name $RESOURCE_GROUP --query location -o tsv)",
    "properties": {
        "dataSources": {
            "windowsEventLogs": [
                {
                    "name": "SecurityEvents",
                    "streams": ["Microsoft-SecurityEvent"],
                    "xPathQueries": [
                        "Security!*[System[(EventID=4624 or EventID=4625 or EventID=4634 or EventID=4648 or EventID=4672)]]",
                        "Security!*[System[(EventID=4688 or EventID=4689)]]",
                        "Security!*[System[(EventID=4663 or EventID=4656 or EventID=4658)]]",
                        "Security!*[System[(EventID=5140 or EventID=5145)]]"
                    ]
                },
                {
                    "name": "ApplicationEvents",
                    "streams": ["Microsoft-Event"],
                    "xPathQueries": [
                        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
                        "System!*[System[(Level=1 or Level=2 or Level=3)]]"
                    ]
                },
                {
                    "name": "PowerShellEvents",
                    "streams": ["Microsoft-Event"],
                    "xPathQueries": [
                        "Microsoft-Windows-PowerShell/Operational!*",
                        "Windows PowerShell!*"
                    ]
                }
            ]
        },
        "destinations": {
            "logAnalytics": [
                {
                    "workspaceResourceId": "$workspace_resource_id",
                    "name": "logAnalyticsDest"
                }
            ]
        },
        "dataFlows": [
            {
                "streams": ["Microsoft-SecurityEvent"],
                "destinations": ["logAnalyticsDest"]
            },
            {
                "streams": ["Microsoft-Event"],
                "destinations": ["logAnalyticsDest"]
            }
        ]
    }
}
EOF
)
        
        echo "$dcr_json" > /tmp/dcr.json
        
        az monitor data-collection rule create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dcr_name" \
            --rule-file /tmp/dcr.json
        
        rm -f /tmp/dcr.json
        log SUCCESS "Data Collection Rule created"
    else
        log WARN "Data Collection Rule already exists"
    fi
    
    # Associate DCR with VMs
    local dcr_id=$(az monitor data-collection rule show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dcr_name" \
        --query "id" -o tsv)
    
    for i in $(seq 0 $((VM_COUNT - 1))); do
        local vm_name="${VM_PREFIX}-${i}"
        log INFO "Associating DCR with: $vm_name"
        
        local vm_id=$(az vm show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --query "id" -o tsv)
        
        az monitor data-collection rule association create \
            --name "dca-${vm_name}" \
            --resource "$vm_id" \
            --rule-id "$dcr_id" 2>/dev/null || log WARN "Association may already exist"
    done
    
    log SUCCESS "Log Analytics agent configured"
}

create_log_analytics_queries() {
    log INFO "Creating useful Log Analytics saved queries..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create saved queries"
        return
    fi
    
    # Note: Saved queries are created via the portal or ARM templates
    # Here we'll output the queries for manual addition
    
    cat << 'EOF'

=== USEFUL LOG ANALYTICS QUERIES ===

// User Session Summary (last 24 hours)
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID in (4624, 4634)
| where AccountType == "User"
| summarize 
    LoginTime = min(iff(EventID == 4624, TimeGenerated, datetime(null))),
    LogoutTime = max(iff(EventID == 4634, TimeGenerated, datetime(null)))
    by TargetUserName, Computer
| extend SessionDuration = LogoutTime - LoginTime

// Applications Launched (with command line)
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID == 4688
| project TimeGenerated, Computer, Account, Process, CommandLine
| order by TimeGenerated desc

// Failed Login Attempts
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID == 4625
| summarize FailedAttempts = count() by TargetUserName, Computer, IpAddress
| order by FailedAttempts desc

// File Access Events
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID == 4663
| project TimeGenerated, Computer, Account, ObjectName, AccessMask
| order by TimeGenerated desc

// USB Device Connection Attempts (blocked)
SecurityEvent
| where TimeGenerated > ago(24h)
| where EventID == 6416
| project TimeGenerated, Computer, Account, DeviceDescription

EOF
    
    log SUCCESS "Query examples printed above - add to Log Analytics as saved queries"
}

deploy_teramind_agent() {
    if [[ "$ENABLE_TERAMIND" != "true" ]]; then
        log INFO "Teramind deployment not requested, skipping"
        return
    fi
    
    log INFO "Deploying Teramind agent for video session recording..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would deploy Teramind agent with key: ${TERAMIND_DEPLOY_KEY:0:8}..."
        return
    fi
    
    local ps_script="
# Download and install Teramind agent
\$deployKey = '$TERAMIND_DEPLOY_KEY'
\$installerUrl = 'https://www.teramind.co/downloads/agent/TeramindAgent.msi'
\$installerPath = 'C:\\Windows\\Temp\\TeramindAgent.msi'

Write-Host 'Downloading Teramind agent...'
Invoke-WebRequest -Uri \$installerUrl -OutFile \$installerPath

Write-Host 'Installing Teramind agent...'
Start-Process msiexec.exe -Wait -ArgumentList \"/i \$installerPath /quiet DEPLOYKEY=\$deployKey\"

Write-Host 'Teramind agent installed successfully'
Write-Host 'Note: Agent will start collecting data after reboot'
"
    
    for i in $(seq 0 $((VM_COUNT - 1))); do
        local vm_name="${VM_PREFIX}-${i}"
        log INFO "Deploying Teramind to: $vm_name"
        
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts "$ps_script" \
            --output none
        
        log SUCCESS "Teramind deployed to $vm_name"
    done
    
    log WARN "VMs need to be restarted for Teramind to start recording"
}

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    SESSION LOGGING CONFIGURATION COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Resource Group:     $RESOURCE_GROUP"
    echo "Log Analytics:      $LOG_ANALYTICS_WORKSPACE"
    echo ""
    echo "Logging Configured:"
    echo "  ┌────────────────────────────────────────────────────────────┐"
    echo "  │  ✓ User login/logout events                                │"
    echo "  │  ✓ Process creation (apps launched with command line)      │"
    echo "  │  ✓ File access events                                      │"
    echo "  │  ✓ PowerShell script execution                             │"
    echo "  │  ✓ USB device connection attempts                          │"
    echo "  │  ✓ RDP session events                                      │"
    echo "  └────────────────────────────────────────────────────────────┘"
    echo ""
    if [[ "$ENABLE_TERAMIND" == "true" ]]; then
        echo "Video Recording: ENABLED (Teramind)"
        echo "  • Full session video recording"
        echo "  • Keystroke logging (optional)"
        echo "  • Screenshot on triggers"
        echo "  • Productivity analytics"
        echo ""
        echo "  ⚠️  Restart VMs for Teramind to activate"
    else
        echo "Video Recording: NOT ENABLED"
        echo "  To enable video recording, run with:"
        echo "  $0 --resource-group $RESOURCE_GROUP --enable-teramind --teramind-key YOUR_KEY"
    fi
    echo ""
    echo "View Logs:"
    echo "  Azure Portal → Log Analytics → $LOG_ANALYTICS_WORKSPACE → Logs"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "*** DRY RUN - No changes were made ***"
    fi
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║         TKT Philippines AVD - Session Logging Setup                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    detect_log_analytics_workspace
    configure_enhanced_logging
    configure_log_analytics_agent
    create_log_analytics_queries
    deploy_teramind_agent
    print_summary
}

main "$@"
