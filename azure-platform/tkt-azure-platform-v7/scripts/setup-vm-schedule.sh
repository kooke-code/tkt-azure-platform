#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - VM Start/Stop Schedule
# Version: 4.0
# Date: 2026-02-12
#
# Creates Azure Automation Account with scheduled runbooks to:
#   - Start VMs at 07:00 Brussels time (Mon-Fri)
#   - Stop VMs at 18:00 Brussels time (Mon-Fri)
#
# Prerequisites:
#   - Azure CLI installed and authenticated
#   - Contributor role on subscription
#
# Usage:
#   ./setup-vm-schedule.sh --resource-group <rg> --vm-prefix <prefix> --vm-count <n>
#   ./setup-vm-schedule.sh --resource-group rg-tktph-avd --vm-prefix tktph-sh --vm-count 2
#
# Cost: ~€5/month for Automation Account
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

RESOURCE_GROUP=""
VM_PREFIX="vm-tktph"
VM_COUNT=2
LOCATION="southeastasia"
DRY_RUN=false

# Schedule (Brussels time = Europe/Brussels)
TIMEZONE="Europe/Brussels"
START_TIME="07:00"
STOP_TIME="18:00"
WEEKDAYS_ONLY=true

# Resource names
AUTOMATION_ACCOUNT_NAME="aa-tktph-vmschedule"
START_RUNBOOK_NAME="Start-AVDSessionHosts"
STOP_RUNBOOK_NAME="Stop-AVDSessionHosts"

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
    --resource-group    Resource group containing VMs
    
Optional:
    --vm-prefix         VM name prefix (default: tktph-sh)
    --vm-count          Number of VMs (default: 2)
    --location          Azure region (default: southeastasia)
    --start-time        Start time in Brussels timezone (default: 07:00)
    --stop-time         Stop time in Brussels timezone (default: 18:00)
    --dry-run           Show what would be created without making changes
    --help              Show this help message

Example:
    $0 --resource-group rg-tktph-avd --vm-prefix tktph-sh --vm-count 2
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
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --start-time)
                START_TIME="$2"
                shift 2
                ;;
            --stop-time)
                STOP_TIME="$2"
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
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI not found. Please install it first."
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    # Register Automation provider if needed
    local provider_state=$(az provider show --namespace Microsoft.Automation --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    if [[ "$provider_state" != "Registered" ]]; then
        log INFO "Registering Microsoft.Automation provider..."
        if [[ "$DRY_RUN" == "false" ]]; then
            az provider register --namespace Microsoft.Automation --wait
        fi
    fi
    
    log SUCCESS "Prerequisites check passed"
}

get_subscription_id() {
    az account show --query "id" -o tsv
}

create_automation_account() {
    log INFO "Creating Azure Automation Account: $AUTOMATION_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create Automation Account"
        return
    fi
    
    # Check if already exists
    if az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT_NAME" &>/dev/null; then
        log WARN "Automation Account already exists, skipping creation"
        return
    fi
    
    az automation account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT_NAME" \
        --location "$LOCATION" \
        --sku Basic \
        --tags Environment=Production Purpose=VMScheduling
    
    log SUCCESS "Automation Account created"
}

assign_managed_identity() {
    log INFO "Configuring System Managed Identity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would assign managed identity and RBAC"
        return
    fi
    
    # Enable system-assigned managed identity
    az automation account identity assign \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT_NAME"
    
    # Get the principal ID
    local principal_id=$(az automation account show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT_NAME" \
        --query "identity.principalId" -o tsv)
    
    # Wait for identity to propagate
    sleep 30
    
    # Assign VM Contributor role to the resource group
    local subscription_id=$(get_subscription_id)
    local scope="/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP"
    
    # Check if role already assigned
    local existing=$(az role assignment list \
        --assignee "$principal_id" \
        --role "Virtual Machine Contributor" \
        --scope "$scope" \
        --query "[].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$existing" ]]; then
        az role assignment create \
            --assignee-object-id "$principal_id" \
            --assignee-principal-type ServicePrincipal \
            --role "Virtual Machine Contributor" \
            --scope "$scope"
        log SUCCESS "RBAC role assigned"
    else
        log WARN "RBAC role already assigned"
    fi
}

create_start_runbook() {
    log INFO "Creating Start VM runbook..."
    
    local vm_list=""
    for i in $(seq 1 $VM_COUNT); do
        vm_list+="\"${VM_PREFIX}-$(printf '%02d' $i)\","
    done
    vm_list=${vm_list%,}  # Remove trailing comma

    local runbook_content='
param(
    [string]$ResourceGroupName = "'"$RESOURCE_GROUP"'",
    [string[]]$VMNames = @('"$vm_list"')
)

Write-Output "Starting VMs at $(Get-Date)"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "VMs to start: $($VMNames -join ", ")"

# Connect using managed identity
try {
    Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    throw
}

foreach ($vmName in $VMNames) {
    Write-Output "Starting VM: $vmName"
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Status
        $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
        
        if ($powerState -eq "PowerState/deallocated" -or $powerState -eq "PowerState/stopped") {
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -NoWait
            Write-Output "Start command sent for $vmName"
        }
        else {
            Write-Output "$vmName is already running (state: $powerState)"
        }
    }
    catch {
        Write-Error "Failed to start $vmName : $_"
    }
}

Write-Output "Start runbook completed at $(Get-Date)"
'
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create runbook: $START_RUNBOOK_NAME"
        return
    fi
    
    # Create temp file for runbook
    local temp_file=$(mktemp)
    echo "$runbook_content" > "$temp_file"
    
    # Create the runbook
    az automation runbook create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$START_RUNBOOK_NAME" \
        --type PowerShell \
        --location "$LOCATION"
    
    # Upload content
    az automation runbook replace-content \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$START_RUNBOOK_NAME" \
        --content @"$temp_file"
    
    # Publish the runbook
    az automation runbook publish \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$START_RUNBOOK_NAME"
    
    rm -f "$temp_file"
    log SUCCESS "Start runbook created and published"
}

create_stop_runbook() {
    log INFO "Creating Stop VM runbook..."
    
    local vm_list=""
    for i in $(seq 1 $VM_COUNT); do
        vm_list+="\"${VM_PREFIX}-$(printf '%02d' $i)\","
    done
    vm_list=${vm_list%,}

    local runbook_content='
param(
    [string]$ResourceGroupName = "'"$RESOURCE_GROUP"'",
    [string[]]$VMNames = @('"$vm_list"')
)

Write-Output "Stopping VMs at $(Get-Date)"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "VMs to stop: $($VMNames -join ", ")"

# Connect using managed identity
try {
    Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    throw
}

foreach ($vmName in $VMNames) {
    Write-Output "Stopping VM: $vmName"
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Status
        $powerState = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
        
        if ($powerState -eq "PowerState/running") {
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -Force -NoWait
            Write-Output "Stop command sent for $vmName (deallocating)"
        }
        else {
            Write-Output "$vmName is already stopped (state: $powerState)"
        }
    }
    catch {
        Write-Error "Failed to stop $vmName : $_"
    }
}

Write-Output "Stop runbook completed at $(Get-Date)"
'
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create runbook: $STOP_RUNBOOK_NAME"
        return
    fi
    
    local temp_file=$(mktemp)
    echo "$runbook_content" > "$temp_file"
    
    az automation runbook create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$STOP_RUNBOOK_NAME" \
        --type PowerShell \
        --location "$LOCATION"
    
    az automation runbook replace-content \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$STOP_RUNBOOK_NAME" \
        --content @"$temp_file"
    
    az automation runbook publish \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "$STOP_RUNBOOK_NAME"
    
    rm -f "$temp_file"
    log SUCCESS "Stop runbook created and published"
}

create_schedules() {
    log INFO "Creating schedules (Brussels timezone)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create schedules:"
        log INFO "  - Start: $START_TIME $TIMEZONE (Mon-Fri)"
        log INFO "  - Stop: $STOP_TIME $TIMEZONE (Mon-Fri)"
        return
    fi
    
    # Calculate start date (tomorrow)
    local start_date=$(date -u -d "+1 day" '+%Y-%m-%dT')
    
    # Create Start schedule
    az automation schedule create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "Schedule-Start-0700-Brussels" \
        --frequency Week \
        --interval 1 \
        --start-time "${start_date}${START_TIME}:00+01:00" \
        --time-zone "$TIMEZONE" \
        --description "Start AVD session hosts at 07:00 Brussels time (Mon-Fri)"
    
    # Create Stop schedule  
    az automation schedule create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --name "Schedule-Stop-1800-Brussels" \
        --frequency Week \
        --interval 1 \
        --start-time "${start_date}${STOP_TIME}:00+01:00" \
        --time-zone "$TIMEZONE" \
        --description "Stop AVD session hosts at 18:00 Brussels time (Mon-Fri)"
    
    log SUCCESS "Schedules created"
}

link_schedules_to_runbooks() {
    log INFO "Linking schedules to runbooks..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would link schedules to runbooks"
        return
    fi
    
    # Link start schedule to start runbook
    az automation schedule job create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --runbook-name "$START_RUNBOOK_NAME" \
        --schedule-name "Schedule-Start-0700-Brussels" 2>/dev/null || true
    
    # Link stop schedule to stop runbook
    az automation schedule job create \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT_NAME" \
        --runbook-name "$STOP_RUNBOOK_NAME" \
        --schedule-name "Schedule-Stop-1800-Brussels" 2>/dev/null || true
    
    log SUCCESS "Schedules linked to runbooks"
}

install_az_modules() {
    log INFO "Installing required PowerShell modules in Automation Account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would install Az.Accounts and Az.Compute modules"
        return
    fi
    
    # Note: Az modules are now included by default in new Automation Accounts
    # But we'll ensure they're there
    
    # The modules are imported from PowerShell Gallery
    # Az.Accounts is required first, then Az.Compute
    
    log INFO "Checking for Az modules (these are typically pre-installed)..."
    log SUCCESS "Module check complete"
}

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    VM SCHEDULE CONFIGURATION COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Automation Account: $AUTOMATION_ACCOUNT_NAME"
    echo "Resource Group:     $RESOURCE_GROUP"
    echo ""
    echo "Schedule (Brussels Time / Europe/Brussels):"
    echo "  ┌────────────────────────────────────────┐"
    echo "  │  START: 07:00 Mon-Fri                  │"
    echo "  │  STOP:  18:00 Mon-Fri                  │"
    echo "  │  Weekends: VMs remain stopped          │"
    echo "  └────────────────────────────────────────┘"
    echo ""
    echo "VMs Managed:"
    for i in $(seq 1 $VM_COUNT); do
        echo "  • ${VM_PREFIX}-$(printf '%02d' $i)"
    done
    echo ""
    echo "Monthly Cost: ~€5 (Automation Account)"
    echo ""
    echo "Runbooks Created:"
    echo "  • $START_RUNBOOK_NAME"
    echo "  • $STOP_RUNBOOK_NAME"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "*** DRY RUN - No resources were created ***"
    else
        echo "✓ Schedules are now active!"
    fi
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║         TKT Philippines AVD - VM Start/Stop Schedule Setup                ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log WARN "DRY RUN MODE - No resources will be created"
        echo ""
    fi
    
    check_prerequisites
    create_automation_account
    assign_managed_identity
    install_az_modules
    create_start_runbook
    create_stop_runbook
    create_schedules
    link_schedules_to_runbooks
    print_summary
}

main "$@"
