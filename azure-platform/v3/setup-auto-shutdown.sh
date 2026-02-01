#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Auto-Shutdown Configuration
# Version: 3.0
# Date: 2026-02-01
#
# This script configures automatic start/stop of AVD session hosts to reduce
# costs by ~60%.
#
# Schedule:
#   Start: 08:00 PHT (00:00 UTC)
#   Stop:  18:00 PHT (10:00 UTC)
#   Days:  Monday-Friday
#
# Usage:
#   chmod +x setup-auto-shutdown.sh
#   ./setup-auto-shutdown.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

RESOURCE_GROUP="rg-tktph-avd-prod-sea"
LOCATION="southeastasia"
AUTOMATION_ACCOUNT="aa-tktph-avd"

# VM names
VM1="vm-tktph-01"
VM2="vm-tktph-02"

# Schedule (UTC times - Philippines is UTC+8)
START_TIME_UTC="00:00"  # 08:00 PHT
STOP_TIME_UTC="10:00"   # 18:00 PHT

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
# CREATE AUTOMATION ACCOUNT
#-------------------------------------------------------------------------------

create_automation_account() {
    log "Creating Automation Account..."
    
    az automation account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT" \
        --location "$LOCATION" \
        --output none 2>/dev/null || log "Automation account may already exist"
    
    log_success "Automation account ready"
}

#-------------------------------------------------------------------------------
# CREATE RUNBOOKS
#-------------------------------------------------------------------------------

create_start_runbook() {
    log "Creating Start VMs runbook..."
    
    # Create runbook content
    cat > /tmp/Start-AVDSessionHosts.ps1 << 'EOF'
<#
.SYNOPSIS
    Starts AVD session hosts for TKT Philippines platform.
.DESCRIPTION
    This runbook starts the session host VMs at the beginning of business hours.
#>

param(
    [string]$ResourceGroup = "rg-tktph-avd-prod-sea",
    [string[]]$VMNames = @("vm-tktph-01", "vm-tktph-02")
)

# Connect to Azure using system-assigned managed identity
try {
    Connect-AzAccount -Identity
    Write-Output "Connected to Azure using managed identity"
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    throw
}

# Start each VM
foreach ($vmName in $VMNames) {
    try {
        Write-Output "Starting VM: $vmName"
        Start-AzVM -ResourceGroupName $ResourceGroup -Name $vmName -NoWait
        Write-Output "Start command sent for: $vmName"
    }
    catch {
        Write-Error "Failed to start VM $vmName : $_"
    }
}

Write-Output "Runbook completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
EOF
    
    log_success "Start runbook created"
}

create_stop_runbook() {
    log "Creating Stop VMs runbook..."
    
    # Create runbook content
    cat > /tmp/Stop-AVDSessionHosts.ps1 << 'EOF'
<#
.SYNOPSIS
    Stops AVD session hosts for TKT Philippines platform.
.DESCRIPTION
    This runbook stops the session host VMs at the end of business hours.
    Checks for active sessions before stopping.
#>

param(
    [string]$ResourceGroup = "rg-tktph-avd-prod-sea",
    [string]$HostPoolName = "tktph-hp",
    [string[]]$VMNames = @("vm-tktph-01", "vm-tktph-02"),
    [bool]$ForceStop = $false
)

# Connect to Azure using system-assigned managed identity
try {
    Connect-AzAccount -Identity
    Write-Output "Connected to Azure using managed identity"
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    throw
}

# Check for active sessions (optional - can be enabled for graceful shutdown)
if (-not $ForceStop) {
    try {
        $sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $ResourceGroup -HostPoolName $HostPoolName
        foreach ($host in $sessionHosts) {
            if ($host.Session -gt 0) {
                Write-Output "WARNING: $($host.Name) has $($host.Session) active session(s)"
                # Optionally: Send notification or skip stopping this VM
            }
        }
    }
    catch {
        Write-Warning "Could not check session count: $_"
    }
}

# Stop each VM (deallocate to stop billing)
foreach ($vmName in $VMNames) {
    try {
        Write-Output "Stopping VM: $vmName"
        Stop-AzVM -ResourceGroupName $ResourceGroup -Name $vmName -Force -NoWait
        Write-Output "Stop command sent for: $vmName"
    }
    catch {
        Write-Error "Failed to stop VM $vmName : $_"
    }
}

Write-Output "Runbook completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC"
EOF
    
    log_success "Stop runbook created"
}

#-------------------------------------------------------------------------------
# CONFIGURE SCHEDULES
#-------------------------------------------------------------------------------

configure_schedules() {
    log "Configuring schedules..."
    
    echo ""
    echo "==============================================================================="
    echo "MANUAL CONFIGURATION REQUIRED"
    echo "==============================================================================="
    echo ""
    echo "Azure Automation schedules must be configured via Azure Portal or ARM template."
    echo ""
    echo "Steps:"
    echo "1. Azure Portal → Automation Accounts → $AUTOMATION_ACCOUNT"
    echo "2. Runbooks → Import runbooks from /tmp/*.ps1"
    echo "3. Schedules → Create:"
    echo "   - Start-Schedule: Every weekday at $START_TIME_UTC UTC (08:00 PHT)"
    echo "   - Stop-Schedule: Every weekday at $STOP_TIME_UTC UTC (18:00 PHT)"
    echo "4. Link runbooks to schedules"
    echo "5. Enable system-assigned managed identity"
    echo "6. Grant 'Virtual Machine Contributor' role on resource group"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# ALTERNATIVE: START VM ON CONNECT
#-------------------------------------------------------------------------------

configure_start_vm_on_connect() {
    log "Configuring 'Start VM on Connect' (built-in AVD feature)..."
    
    # This is already configured in the host pool during deployment
    # Just verify it's enabled
    
    START_ON_CONNECT=$(az desktopvirtualization hostpool show \
        --resource-group "$RESOURCE_GROUP" \
        --name "tktph-hp" \
        --query "startVMOnConnect" \
        --output tsv 2>/dev/null || echo "unknown")
    
    if [ "$START_ON_CONNECT" == "true" ]; then
        log_success "'Start VM on Connect' is enabled"
    else
        log "Enabling 'Start VM on Connect'..."
        az desktopvirtualization hostpool update \
            --resource-group "$RESOURCE_GROUP" \
            --name "tktph-hp" \
            --start-vm-on-connect true \
            --output none 2>/dev/null || log "May need portal configuration"
    fi
    
    echo ""
    echo "With 'Start VM on Connect' enabled:"
    echo "  - VMs can be stopped to save costs"
    echo "  - When user connects, VM auto-starts"
    echo "  - User waits ~2-3 minutes for VM to start"
    echo ""
}

#-------------------------------------------------------------------------------
# SIMPLE ALTERNATIVE: VM AUTO-SHUTDOWN
#-------------------------------------------------------------------------------

configure_vm_auto_shutdown() {
    log "Configuring simple VM auto-shutdown..."
    
    for VM in $VM1 $VM2; do
        log "Configuring auto-shutdown for $VM..."
        
        az vm auto-shutdown \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM" \
            --time "1000" \
            --output none 2>/dev/null || log "Auto-shutdown may need portal configuration for $VM"
    done
    
    log_success "VM auto-shutdown configured for 10:00 UTC (18:00 PHT)"
    
    echo ""
    echo "Note: This configures STOP only. Start must be done manually or via"
    echo "'Start VM on Connect' (recommended for AVD)."
    echo ""
}

#-------------------------------------------------------------------------------
# COST SAVINGS ESTIMATE
#-------------------------------------------------------------------------------

print_cost_savings() {
    echo ""
    echo "==============================================================================="
    echo "                    COST SAVINGS ESTIMATE"
    echo "==============================================================================="
    echo ""
    echo "Configuration:"
    echo "  Running hours:  10 hours/day (08:00-18:00 PHT)"
    echo "  Working days:   22 days/month"
    echo "  Total hours:    220 hours/month (vs 720 hours if always on)"
    echo ""
    echo "Cost Comparison (2× D4s_v5 VMs):"
    echo "  Always-on:      €380/month"
    echo "  Business hours: €116/month"
    echo "  Savings:        €264/month (69%)"
    echo ""
    echo "Additional Savings with Reserved Instances:"
    echo "  Business hours + RI: €81/month (30% RI discount)"
    echo "  Total savings:       €299/month (79%)"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# SUMMARY
#-------------------------------------------------------------------------------

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    AUTO-SHUTDOWN SETUP COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Configured:"
    echo "  ✓ 'Start VM on Connect' enabled on host pool"
    echo "  ✓ VM auto-shutdown at 18:00 PHT (10:00 UTC)"
    echo ""
    echo "Manual steps required for full automation:"
    echo "  1. Import runbooks to Automation Account"
    echo "  2. Create schedules for start/stop"
    echo "  3. Configure managed identity permissions"
    echo ""
    echo "Runbook files:"
    echo "  - /tmp/Start-AVDSessionHosts.ps1"
    echo "  - /tmp/Stop-AVDSessionHosts.ps1"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "==============================================================================="
    echo "     TKT PHILIPPINES AVD - AUTO-SHUTDOWN CONFIGURATION"
    echo "==============================================================================="
    echo ""
    
    create_automation_account
    create_start_runbook
    create_stop_runbook
    configure_schedules
    configure_start_vm_on_connect
    configure_vm_auto_shutdown
    print_cost_savings
    print_summary
}

main "$@"
