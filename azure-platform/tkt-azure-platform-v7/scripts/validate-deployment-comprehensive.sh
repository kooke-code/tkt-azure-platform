#!/bin/bash
#===============================================================================
# TKT Philippines AVD - Comprehensive Validation Script
# Version: 7.0
# 
# Validates all deployment components including:
# - Infrastructure (RG, VNet, Storage)
# - AVD Control Plane (Host Pool, Workspace, App Group)
# - Session Hosts (VMs, Entra ID Join, Health)
# - Applications (Teams, Office, WebRTC)
# - Identity (Users, Groups, RBAC)
# - Configuration (FSLogix, RDP Properties)
#
# This script auto-discovers resources - no hardcoded names!
#===============================================================================

# Don't exit on errors - we want to continue and report all failures
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0

# Configuration - will be auto-discovered
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
SUBSCRIPTION_ID=""
VNET_NAME=""
SUBNET_NAME=""
NSG_NAME=""
STORAGE_ACCOUNT=""
LOG_ANALYTICS=""
HOSTPOOL_NAME=""
WORKSPACE_NAME=""
APP_GROUP_NAME=""
VM_NAMES=()
SECURITY_GROUP=""

#===============================================================================
# Helper Functions
#===============================================================================

log_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARN++))
}

log_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

#===============================================================================
# Auto-Discovery Function
#===============================================================================

discover_resources() {
    log_section "AUTO-DISCOVERING RESOURCES"
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
    if [ -n "$SUBSCRIPTION_ID" ]; then
        log_info "Subscription: $SUBSCRIPTION_ID"
    else
        log_fail "Could not get subscription ID"
        return 1
    fi
    
    # If resource group not provided, try to find AVD resource groups
    if [ -z "$RESOURCE_GROUP" ]; then
        RESOURCE_GROUP=$(az group list --query "[?contains(name, 'avd') || contains(name, 'AVD')].name | [0]" -o tsv 2>/dev/null)
        if [ -z "$RESOURCE_GROUP" ]; then
            log_fail "No resource group provided and could not auto-discover"
            echo "  Usage: $0 --resource-group <name>"
            return 1
        fi
    fi
    log_info "Resource Group: $RESOURCE_GROUP"
    
    # Discover VNet
    VNET_NAME=$(az network vnet list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$VNET_NAME" ]; then
        log_info "VNet: $VNET_NAME"
        
        # Discover Subnet
        SUBNET_NAME=$(az network vnet subnet list -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query "[0].name" -o tsv 2>/dev/null)
        log_info "Subnet: $SUBNET_NAME"
    fi
    
    # Discover NSG
    NSG_NAME=$(az network nsg list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$NSG_NAME" ]; then
        log_info "NSG: $NSG_NAME"
    fi
    
    # Discover Storage Account
    STORAGE_ACCOUNT=$(az storage account list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log_info "Storage Account: $STORAGE_ACCOUNT"
    fi
    
    # Discover Log Analytics
    LOG_ANALYTICS=$(az monitor log-analytics workspace list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    if [ -n "$LOG_ANALYTICS" ]; then
        log_info "Log Analytics: $LOG_ANALYTICS"
    fi
    
    # Discover Host Pool
    HOSTPOOL_NAME=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools?api-version=2024-04-03" --query "value[0].name" -o tsv 2>/dev/null)
    if [ -n "$HOSTPOOL_NAME" ]; then
        log_info "Host Pool: $HOSTPOOL_NAME"
    fi
    
    # Discover Workspace
    WORKSPACE_NAME=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/workspaces?api-version=2024-04-03" --query "value[0].name" -o tsv 2>/dev/null)
    if [ -n "$WORKSPACE_NAME" ]; then
        log_info "Workspace: $WORKSPACE_NAME"
    fi
    
    # Discover Application Group
    APP_GROUP_NAME=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups?api-version=2024-04-03" --query "value[0].name" -o tsv 2>/dev/null)
    if [ -n "$APP_GROUP_NAME" ]; then
        log_info "App Group: $APP_GROUP_NAME"
    fi
    
    # Discover VMs (session hosts)
    VM_NAMES=($(az vm list -g "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null))
    if [ ${#VM_NAMES[@]} -gt 0 ]; then
        log_info "VMs found: ${#VM_NAMES[@]} (${VM_NAMES[*]})"
    fi
    
    # Discover Security Group (look for AVD-related groups)
    SECURITY_GROUP=$(az ad group list --query "[?contains(displayName, 'AVD') || contains(displayName, 'Philippines')].displayName | [0]" -o tsv 2>/dev/null)
    if [ -n "$SECURITY_GROUP" ]; then
        log_info "Security Group: $SECURITY_GROUP"
    fi
    
    echo ""
}

check_command() {
    if eval "$1" &>/dev/null; then
        log_pass "$2"
        return 0
    else
        log_fail "$2"
        return 1
    fi
}

#===============================================================================
# Validation Functions
#===============================================================================

validate_infrastructure() {
    log_section "INFRASTRUCTURE"
    
    # Resource Group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_pass "Resource group exists: $RESOURCE_GROUP"
    else
        log_fail "Resource group not found: $RESOURCE_GROUP"
        return 1
    fi
    
    # Virtual Network
    if [ -n "$VNET_NAME" ]; then
        log_pass "Virtual network exists: $VNET_NAME"
    else
        log_fail "No virtual network found"
    fi
    
    # Subnet
    if [ -n "$SUBNET_NAME" ]; then
        log_pass "Subnet exists: $SUBNET_NAME"
    else
        log_fail "No subnet found"
    fi
    
    # NSG
    if [ -n "$NSG_NAME" ]; then
        log_pass "NSG exists: $NSG_NAME"
        
        # Check NSG is attached to subnet
        if [ -n "$VNET_NAME" ] && [ -n "$SUBNET_NAME" ]; then
            NSG_ID=$(az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" -n "$SUBNET_NAME" --query "networkSecurityGroup.id" -o tsv 2>/dev/null)
            if [ -n "$NSG_ID" ] && [ "$NSG_ID" != "null" ]; then
                log_pass "NSG attached to subnet"
            else
                log_fail "NSG not attached to subnet"
            fi
        fi
    else
        log_fail "No NSG found"
    fi
    
    # Storage Account
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log_pass "Storage account exists: $STORAGE_ACCOUNT"
        
        # Check FSLogix share
        if az storage share show --account-name "$STORAGE_ACCOUNT" --name "profiles" &>/dev/null; then
            log_pass "FSLogix share exists: profiles"
        else
            log_fail "FSLogix share not found: profiles"
        fi
        
        # Check shared drive (V6.3)
        if az storage share show --account-name "$STORAGE_ACCOUNT" --name "shared" &>/dev/null; then
            log_pass "Shared drive exists: shared"
        else
            log_warn "Shared drive not found: shared (optional)"
        fi
    else
        log_fail "No storage account found"
    fi
    
    # Log Analytics
    if [ -n "$LOG_ANALYTICS" ]; then
        log_pass "Log Analytics workspace exists: $LOG_ANALYTICS"
    else
        log_fail "No Log Analytics workspace found"
    fi
}

validate_avd_control_plane() {
    log_section "AVD CONTROL PLANE"
    
    # Workspace
    if [ -n "$WORKSPACE_NAME" ]; then
        log_pass "Workspace exists: $WORKSPACE_NAME"
    else
        log_fail "No workspace found"
    fi
    
    # Host Pool
    if [ -n "$HOSTPOOL_NAME" ]; then
        HP_RESPONSE=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME?api-version=2024-04-03" 2>/dev/null)
        if [ -n "$HP_RESPONSE" ]; then
            log_pass "Host pool exists: $HOSTPOOL_NAME"
            
            # Check RDP properties for Entra ID join
            RDP_PROPS=$(echo "$HP_RESPONSE" | grep -o '"customRdpProperty":"[^"]*"' | cut -d'"' -f4)
            if [[ "$RDP_PROPS" == *"targetisaadjoined:i:1"* ]]; then
                log_pass "Host pool configured for Entra ID join (targetisaadjoined:i:1)"
            else
                log_fail "Host pool missing Entra ID RDP property (targetisaadjoined:i:1)"
            fi
            
            # Check host pool type
            HP_TYPE=$(echo "$HP_RESPONSE" | grep -o '"hostPoolType":"[^"]*"' | cut -d'"' -f4)
            log_info "Host pool type: $HP_TYPE"
            
            # Check max session limit
            MAX_SESSIONS=$(echo "$HP_RESPONSE" | grep -o '"maxSessionLimit":[0-9]*' | cut -d':' -f2)
            log_info "Max sessions per host: $MAX_SESSIONS"
        fi
    else
        log_fail "No host pool found"
    fi
    
    # Application Group
    if [ -n "$APP_GROUP_NAME" ]; then
        log_pass "Application group exists: $APP_GROUP_NAME"
    else
        log_fail "No application group found"
    fi
}

validate_session_hosts() {
    log_section "SESSION HOSTS"
    
    if [ ${#VM_NAMES[@]} -eq 0 ]; then
        log_fail "No VMs found in resource group"
        return
    fi
    
    for VM_NAME in "${VM_NAMES[@]}"; do
        echo ""
        echo -e "  ${BLUE}--- $VM_NAME ---${NC}"
        
        # Check VM exists and is running
        VM_STATUS=$(az vm get-instance-view -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "instanceView.statuses[1].displayStatus" -o tsv 2>/dev/null)
        if [ "$VM_STATUS" == "VM running" ]; then
            log_pass "VM running"
        else
            log_fail "VM not running: $VM_STATUS"
            continue
        fi
        
        # Check managed identity
        IDENTITY=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "identity.type" -o tsv 2>/dev/null)
        if [ "$IDENTITY" == "SystemAssigned" ]; then
            log_pass "Managed identity enabled"
        else
            log_fail "Managed identity not enabled"
        fi
        
        # Check session host status in AVD
        if [ -n "$HOSTPOOL_NAME" ]; then
            SH_STATUS=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME/sessionHosts/$VM_NAME?api-version=2024-04-03" --query "properties.status" -o tsv 2>/dev/null)
            if [ "$SH_STATUS" == "Available" ]; then
                log_pass "Session host status: Available"
            else
                log_fail "Session host status: $SH_STATUS"
            fi
            
            # Check health checks
            HEALTH_RESPONSE=$(az rest --method GET --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME/sessionHosts/$VM_NAME?api-version=2024-04-03" 2>/dev/null)
            
            if [ -n "$HEALTH_RESPONSE" ]; then
                # Check AAD health check
                if echo "$HEALTH_RESPONSE" | grep -q '"healthCheckName":"AADJoinedHealthCheck".*"healthCheckResult":"HealthCheckSucceeded"'; then
                    log_pass "Entra ID join health check passed"
                else
                    log_fail "Entra ID join health check failed"
                fi
                
                # Check SxS stack
                if echo "$HEALTH_RESPONSE" | grep -q '"healthCheckName":"SxSStackListenerCheck".*"healthCheckResult":"HealthCheckSucceeded"'; then
                    log_pass "SxS stack listener health check passed"
                else
                    log_fail "SxS stack listener health check failed"
                fi
            fi
        fi
        
        # Check AADLoginForWindows extension
        AAD_EXT=$(az vm extension show -g "$RESOURCE_GROUP" --vm-name "$VM_NAME" --name "AADLoginForWindows" --query "provisioningState" -o tsv 2>/dev/null)
        if [ "$AAD_EXT" == "Succeeded" ]; then
            log_pass "AADLoginForWindows extension installed"
        else
            log_fail "AADLoginForWindows extension not installed"
        fi
    done
}

validate_applications() {
    log_section "APPLICATIONS (via VM run-command)"
    
    if [ ${#VM_NAMES[@]} -eq 0 ]; then
        log_fail "No VMs to check"
        return
    fi
    
    for VM_NAME in "${VM_NAMES[@]}"; do
        echo ""
        echo -e "  ${BLUE}--- $VM_NAME ---${NC}"
        
        # Run validation script on VM
        RESULT=$(az vm run-command invoke -g "$RESOURCE_GROUP" -n "$VM_NAME" \
            --command-id RunPowerShellScript \
            --scripts '
                $results = @{}
                
                # Check Teams
                $teams = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*MSTeams*" }
                $results["Teams"] = if ($teams) { "Installed" } else { "Not Installed" }
                
                # Check WebRTC Redirector
                $webrtc = Get-Service -Name MsRdcWebRTCSvc -ErrorAction SilentlyContinue
                $results["WebRTC"] = if ($webrtc) { "Installed - $($webrtc.Status)" } else { "Not Installed" }
                
                # Check IsWVDEnvironment registry
                $wvdReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name IsWVDEnvironment -ErrorAction SilentlyContinue
                $results["IsWVDEnvironment"] = if ($wvdReg.IsWVDEnvironment -eq 1) { "Set" } else { "Not Set" }
                
                # Check Office
                $office = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
                $results["Office"] = if ($office) { "Installed - $($office.VersionToReport)" } else { "Not Installed" }
                
                # Check FSLogix
                $frx = Get-Service -Name frxsvc -ErrorAction SilentlyContinue
                $results["FSLogix"] = if ($frx) { "Installed - $($frx.Status)" } else { "Not Installed" }
                
                # Check Entra ID Join
                $dsreg = dsregcmd /status | Select-String "AzureAdJoined"
                $results["EntraIDJoin"] = if ($dsreg -match "YES") { "Joined" } else { "Not Joined" }
                
                # Output results
                $results.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }
            ' --query "value[0].message" -o tsv 2>/dev/null)
        
        # Parse results
        if [[ "$RESULT" == *"Teams: Installed"* ]]; then
            log_pass "Teams installed"
        else
            log_fail "Teams not installed"
        fi
        
        if [[ "$RESULT" == *"WebRTC: Installed"* ]]; then
            log_pass "WebRTC Redirector installed"
        else
            log_fail "WebRTC Redirector not installed"
        fi
        
        if [[ "$RESULT" == *"IsWVDEnvironment: Set"* ]]; then
            log_pass "IsWVDEnvironment registry set"
        else
            log_fail "IsWVDEnvironment registry not set"
        fi
        
        if [[ "$RESULT" == *"Office: Installed"* ]]; then
            log_pass "Microsoft 365 Apps installed"
        else
            log_warn "Microsoft 365 Apps not installed"
        fi
        
        if [[ "$RESULT" == *"FSLogix: Installed"* ]]; then
            log_pass "FSLogix installed"
        else
            log_fail "FSLogix not installed"
        fi
        
        if [[ "$RESULT" == *"EntraIDJoin: Joined"* ]]; then
            log_pass "Entra ID joined (dsregcmd)"
        else
            log_fail "Entra ID not joined"
        fi
    done
}

validate_identity() {
    log_section "IDENTITY & RBAC"
    
    # Check security group exists
    if [ -n "$SECURITY_GROUP" ]; then
        GROUP_ID=$(az ad group show -g "$SECURITY_GROUP" --query id -o tsv 2>/dev/null)
        if [ -n "$GROUP_ID" ]; then
            log_pass "Security group exists: $SECURITY_GROUP"
            
            # Count members
            MEMBER_COUNT=$(az ad group member list -g "$SECURITY_GROUP" --query "length(@)" -o tsv 2>/dev/null)
            log_info "Group members: $MEMBER_COUNT"
        else
            log_fail "Security group not found: $SECURITY_GROUP"
        fi
    else
        log_warn "No security group discovered"
    fi
    
    # Discover users (look for consultant pattern)
    USER_COUNT=$(az ad user list --query "[?contains(userPrincipalName, 'consultant')].userPrincipalName" -o tsv 2>/dev/null | wc -l)
    if [ "$USER_COUNT" -gt 0 ]; then
        log_pass "Found $USER_COUNT consultant user(s)"
    else
        log_warn "No consultant users found"
    fi
    
    # Check RBAC - Desktop Virtualization User on App Group
    if [ -n "$APP_GROUP_NAME" ]; then
        DVU_ROLE=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APP_GROUP_NAME" --query "[?roleDefinitionName=='Desktop Virtualization User'].principalId" -o tsv 2>/dev/null)
        if [ -n "$DVU_ROLE" ]; then
            log_pass "Desktop Virtualization User role assigned on app group"
        else
            log_fail "Desktop Virtualization User role not assigned"
        fi
    fi
    
    # Check RBAC - Virtual Machine User Login on VMs
    for VM_NAME in "${VM_NAMES[@]}"; do
        VM_LOGIN_ROLE=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" --query "[?roleDefinitionName=='Virtual Machine User Login'].principalId" -o tsv 2>/dev/null)
        if [ -n "$VM_LOGIN_ROLE" ]; then
            log_pass "VM User Login role assigned on $VM_NAME"
        else
            log_fail "VM User Login role not assigned on $VM_NAME"
        fi
    done
}

validate_entra_devices() {
    log_section "ENTRA ID DEVICES"
    
    if [ ${#VM_NAMES[@]} -eq 0 ]; then
        log_warn "No VMs to check"
        return
    fi
    
    for VM_NAME in "${VM_NAMES[@]}"; do
        # Check for device in Entra ID
        DEVICE_ID=$(az rest --method GET --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq '$VM_NAME'" --query "value[0].id" -o tsv 2>/dev/null)
        if [ -n "$DEVICE_ID" ] && [ "$DEVICE_ID" != "null" ]; then
            log_pass "Device registered in Entra ID: $VM_NAME"
        else
            log_fail "Device not found in Entra ID: $VM_NAME"
        fi
    done
}

#===============================================================================
# Main
#===============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}║     TKT Philippines AVD - Comprehensive Validation           ║${NC}"
    echo -e "${BLUE}║                        Version 7.0                            ║${NC}"
    echo -e "${BLUE}║                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    # Auto-discover resources
    discover_resources
    
    # Run all validations
    validate_infrastructure
    validate_avd_control_plane
    validate_session_hosts
    validate_applications
    validate_identity
    validate_entra_devices
    
    # Summary
    log_section "VALIDATION SUMMARY"
    echo ""
    echo -e "  ${GREEN}Passed:${NC}   $PASS"
    echo -e "  ${RED}Failed:${NC}   $FAIL"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN"
    echo ""
    
    TOTAL=$((PASS + FAIL))
    if [ $TOTAL -gt 0 ]; then
        SCORE=$((PASS * 100 / TOTAL))
        echo -e "  Score: ${YELLOW}${SCORE}%${NC}"
    fi
    
    echo ""
    
    if [ $FAIL -eq 0 ]; then
        echo -e "  ${GREEN}✓ All critical checks passed!${NC}"
        echo ""
        return 0
    else
        echo -e "  ${RED}✗ Some checks failed. Review above for details.${NC}"
        echo ""
        return 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --host-pool|-hp)
            HOSTPOOL_NAME="$2"
            shift 2
            ;;
        --vm-count|-c)
            VM_COUNT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -g, --resource-group    Resource group name"
            echo "  -hp, --host-pool        Host pool name"
            echo "  -c, --vm-count          Number of VMs to check"
            echo "  -h, --help              Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
