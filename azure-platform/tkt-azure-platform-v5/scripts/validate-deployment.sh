#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Deployment Validation Script
# Version: 4.0
# Date: 2026-02-12
#
# This script performs comprehensive validation of AVD deployment including:
#   - Resource existence and configuration checks
#   - Network connectivity tests
#   - AVD service health checks
#   - User authentication tests
#   - FSLogix profile tests
#
# Prerequisites:
#   - Azure CLI authenticated with Reader role minimum
#   - Deployment completed (all phases)
#
# Usage:
#   ./validate-deployment.sh --resource-group <rg> --host-pool <hp> [--output json]
#
# Output:
#   - Console summary with pass/fail status
#   - JSON report file (optional)
#===============================================================================

set -uo pipefail
# Ensure script runs in bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash $0 $*"
    exit 1
fi#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_FILE:-/tmp/avd-validation-${TIMESTAMP}.log}"

# Test results
declare -A TEST_RESULTS
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Output format
OUTPUT_FORMAT="console"
OUTPUT_FILE=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)    echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [PASS]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        ERROR)   echo -e "${RED}[$timestamp] [FAIL]${NC} $message" ;;
        TEST)    echo -e "${CYAN}[$timestamp] [TEST]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Validate AVD deployment and run smoke tests.

Options:
    --resource-group <name>    Azure resource group name
    --host-pool <name>         AVD host pool name
    --workspace <name>         AVD workspace name (optional, auto-detected)
    --vm-prefix <prefix>       Session host VM prefix (optional, auto-detected)
    --output <format>          Output format: console, json (default: console)
    --output-file <path>       Output file path for JSON report
    -h, --help                 Show this help message

Examples:
    $SCRIPT_NAME --resource-group rg-tktph-avd --host-pool tktph-hp
    
    $SCRIPT_NAME --resource-group rg-tktph-avd --host-pool tktph-hp \\
        --output json --output-file validation-report.json
EOF
    exit 0
}

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------

parse_args() {
    RESOURCE_GROUP=""
    HOST_POOL=""
    WORKSPACE=""
    VM_PREFIX=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
            --host-pool) HOST_POOL="$2"; shift 2 ;;
            --workspace) WORKSPACE="$2"; shift 2 ;;
            --vm-prefix) VM_PREFIX="$2"; shift 2 ;;
            --output) OUTPUT_FORMAT="$2"; shift 2 ;;
            --output-file) OUTPUT_FILE="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) log ERROR "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "Resource group is required (--resource-group)"
        exit 1
    fi
    if [[ -z "$HOST_POOL" ]]; then
        log ERROR "Host pool is required (--host-pool)"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Test Result Tracking
#-------------------------------------------------------------------------------

record_test() {
    local test_name="$1"
    local status="$2"  # PASS, FAIL, WARN
    local message="$3"
    
    TEST_RESULTS["$test_name"]="$status|$message"
    
    case "$status" in
        PASS) ((TESTS_PASSED++)); log SUCCESS "$test_name: $message" ;;
        FAIL) ((TESTS_FAILED++)); log ERROR "$test_name: $message" ;;
        WARN) ((TESTS_WARNED++)); log WARN "$test_name: $message" ;;
    esac
}

#-------------------------------------------------------------------------------
# Resource Validation Tests
#-------------------------------------------------------------------------------

test_resource_group() {
    log TEST "Checking resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        local location=$(az group show --name "$RESOURCE_GROUP" --query "location" -o tsv)
        record_test "ResourceGroup" "PASS" "Exists in $location"
    else
        record_test "ResourceGroup" "FAIL" "Resource group not found"
        return 1
    fi
}

test_virtual_network() {
    log TEST "Checking virtual network..."
    
    local vnet_name=$(az network vnet list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$vnet_name" ]]; then
        local address_space=$(az network vnet show --resource-group "$RESOURCE_GROUP" \
            --name "$vnet_name" --query "addressSpace.addressPrefixes[0]" -o tsv)
        record_test "VirtualNetwork" "PASS" "$vnet_name ($address_space)"
    else
        record_test "VirtualNetwork" "FAIL" "No virtual network found"
    fi
}

test_network_security_group() {
    log TEST "Checking network security group..."
    
    local nsg_name=$(az network nsg list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$nsg_name" ]]; then
        local rule_count=$(az network nsg rule list --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$nsg_name" --query "length(@)" -o tsv)
        record_test "NSG" "PASS" "$nsg_name with $rule_count rules"
        
        # Check for required AVD rules
        local has_avd_rule=$(az network nsg rule list --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$nsg_name" --query "[?contains(name, 'AVD') || contains(name, 'WindowsVirtualDesktop')]" -o tsv)
        
        if [[ -n "$has_avd_rule" ]]; then
            record_test "NSG-AVD-Rules" "PASS" "AVD service tag rules configured"
        else
            record_test "NSG-AVD-Rules" "WARN" "No explicit AVD rules found (may use defaults)"
        fi
    else
        record_test "NSG" "FAIL" "No NSG found"
    fi
}

test_storage_account() {
    log TEST "Checking storage account..."
    
    local storage_name=$(az storage account list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$storage_name" ]]; then
        local kind=$(az storage account show --name "$storage_name" \
            --resource-group "$RESOURCE_GROUP" --query "kind" -o tsv)
        local sku=$(az storage account show --name "$storage_name" \
            --resource-group "$RESOURCE_GROUP" --query "sku.name" -o tsv)
        
        if [[ "$kind" == "FileStorage" ]]; then
            record_test "StorageAccount" "PASS" "$storage_name ($kind, $sku)"
        else
            record_test "StorageAccount" "WARN" "$storage_name is $kind (FileStorage recommended)"
        fi
        
        # Check for FSLogix share
        local storage_key=$(az storage account keys list --account-name "$storage_name" \
            --resource-group "$RESOURCE_GROUP" --query "[0].value" -o tsv 2>/dev/null)
        
        if az storage share show --name "profiles" --account-name "$storage_name" \
            --account-key "$storage_key" &>/dev/null; then
            record_test "FSLogixShare" "PASS" "Profile share exists"
        else
            record_test "FSLogixShare" "WARN" "No 'profiles' share found"
        fi
    else
        record_test "StorageAccount" "FAIL" "No storage account found"
    fi
}

test_log_analytics() {
    log TEST "Checking Log Analytics workspace..."
    
    local workspace_name=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$workspace_name" ]]; then
        local retention=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" --workspace-name "$workspace_name" \
            --query "retentionInDays" -o tsv)
        record_test "LogAnalytics" "PASS" "$workspace_name ($retention day retention)"
    else
        record_test "LogAnalytics" "WARN" "No Log Analytics workspace found"
    fi
}

#-------------------------------------------------------------------------------
# AVD Service Tests
#-------------------------------------------------------------------------------

test_avd_workspace() {
    log TEST "Checking AVD workspace..."
    
    if [[ -z "$WORKSPACE" ]]; then
        WORKSPACE=$(az desktopvirtualization workspace list \
            --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    fi
    
    if [[ -n "$WORKSPACE" ]]; then
        local friendly_name=$(az desktopvirtualization workspace show \
            --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE" \
            --query "friendlyName" -o tsv 2>/dev/null)
        record_test "AVD-Workspace" "PASS" "$WORKSPACE ($friendly_name)"
    else
        record_test "AVD-Workspace" "FAIL" "No AVD workspace found"
    fi
}

test_avd_hostpool() {
    log TEST "Checking AVD host pool..."
    
    if az desktopvirtualization hostpool show --resource-group "$RESOURCE_GROUP" \
        --name "$HOST_POOL" &>/dev/null; then
        
        local pool_type=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" --name "$HOST_POOL" \
            --query "hostPoolType" -o tsv)
        local lb_type=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" --name "$HOST_POOL" \
            --query "loadBalancerType" -o tsv)
        local max_sessions=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" --name "$HOST_POOL" \
            --query "maxSessionLimit" -o tsv)
        
        record_test "AVD-HostPool" "PASS" "$HOST_POOL ($pool_type, $lb_type, max $max_sessions sessions)"
        
        # Check registration token
        local token_expiry=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" --name "$HOST_POOL" \
            --query "registrationInfo.expirationTime" -o tsv 2>/dev/null)
        
        if [[ -n "$token_expiry" && "$token_expiry" != "null" ]]; then
            record_test "AVD-RegistrationToken" "PASS" "Valid until $token_expiry"
        else
            record_test "AVD-RegistrationToken" "WARN" "No active registration token"
        fi
    else
        record_test "AVD-HostPool" "FAIL" "Host pool '$HOST_POOL' not found"
    fi
}

test_avd_application_group() {
    log TEST "Checking AVD application group..."
    
    local app_groups=$(az desktopvirtualization applicationgroup list \
        --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null)
    
    if [[ -n "$app_groups" ]]; then
        local count=$(echo "$app_groups" | wc -l)
        local first_group=$(echo "$app_groups" | head -1)
        
        local ag_type=$(az desktopvirtualization applicationgroup show \
            --resource-group "$RESOURCE_GROUP" --name "$first_group" \
            --query "applicationGroupType" -o tsv)
        
        record_test "AVD-AppGroup" "PASS" "$count application group(s) ($ag_type)"
    else
        record_test "AVD-AppGroup" "FAIL" "No application groups found"
    fi
}

test_avd_session_hosts() {
    log TEST "Checking AVD session hosts..."
    
    local session_hosts=$(az desktopvirtualization sessionhost list \
        --resource-group "$RESOURCE_GROUP" --host-pool-name "$HOST_POOL" \
        --query "[].name" -o tsv 2>/dev/null)
    
    if [[ -n "$session_hosts" ]]; then
        local total=0
        local available=0
        local unavailable=0
        
        while IFS= read -r host; do
            ((total++))
            local status=$(az desktopvirtualization sessionhost show \
                --resource-group "$RESOURCE_GROUP" --host-pool-name "$HOST_POOL" \
                --name "$host" --query "status" -o tsv 2>/dev/null)
            
            if [[ "$status" == "Available" ]]; then
                ((available++))
            else
                ((unavailable++))
            fi
        done <<< "$session_hosts"
        
        if [[ $available -eq $total ]]; then
            record_test "AVD-SessionHosts" "PASS" "$available/$total hosts available"
        elif [[ $available -gt 0 ]]; then
            record_test "AVD-SessionHosts" "WARN" "$available/$total hosts available ($unavailable unavailable)"
        else
            record_test "AVD-SessionHosts" "FAIL" "No hosts available ($total total)"
        fi
    else
        record_test "AVD-SessionHosts" "FAIL" "No session hosts registered"
    fi
}

#-------------------------------------------------------------------------------
# Session Host Tests
#-------------------------------------------------------------------------------

test_session_host_vms() {
    log TEST "Checking session host VMs..."
    
    # Auto-detect VM prefix if not provided
    if [[ -z "$VM_PREFIX" ]]; then
        VM_PREFIX=$(az vm list --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null | sed 's/-[0-9]*$//')
    fi
    
    local vms=$(az vm list --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, '$VM_PREFIX')].name" -o tsv 2>/dev/null)
    
    if [[ -n "$vms" ]]; then
        local running=0
        local stopped=0
        
        while IFS= read -r vm; do
            local state=$(az vm get-instance-view --resource-group "$RESOURCE_GROUP" \
                --name "$vm" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
            
            if [[ "$state" == "VM running" ]]; then
                ((running++))
            else
                ((stopped++))
            fi
        done <<< "$vms"
        
        local total=$((running + stopped))
        if [[ $running -eq $total ]]; then
            record_test "SessionHost-VMs" "PASS" "$running/$total VMs running"
        else
            record_test "SessionHost-VMs" "WARN" "$running/$total VMs running ($stopped stopped)"
        fi
    else
        record_test "SessionHost-VMs" "FAIL" "No session host VMs found"
    fi
}

test_session_host_extensions() {
    log TEST "Checking VM extensions..."
    
    local vm_name=$(az vm list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -n "$vm_name" ]]; then
        local extensions=$(az vm extension list --resource-group "$RESOURCE_GROUP" \
            --vm-name "$vm_name" --query "[].name" -o tsv 2>/dev/null)
        
        # Check for Azure Monitor Agent
        if echo "$extensions" | grep -qi "AzureMonitorWindowsAgent\|MicrosoftMonitoringAgent"; then
            record_test "VM-MonitoringAgent" "PASS" "Monitoring agent installed"
        else
            record_test "VM-MonitoringAgent" "WARN" "No monitoring agent detected"
        fi
        
        # Check for AAD Login extension (optional)
        if echo "$extensions" | grep -qi "AADLoginForWindows"; then
            record_test "VM-AADLogin" "PASS" "AAD Login extension installed"
        else
            record_test "VM-AADLogin" "WARN" "AAD Login extension not found (may use hybrid join)"
        fi
    fi
}

#-------------------------------------------------------------------------------
# Connectivity Tests
#-------------------------------------------------------------------------------

test_avd_gateway_connectivity() {
    log TEST "Checking AVD gateway connectivity..."
    
    # AVD gateway endpoints
    local endpoints=(
        "rdweb.wvd.microsoft.com"
        "rdbroker.wvd.microsoft.com"
        "rdgateway.wvd.microsoft.com"
    )
    
    local reachable=0
    for endpoint in "${endpoints[@]}"; do
        if nc -z -w5 "$endpoint" 443 &>/dev/null; then
            ((reachable++))
        fi
    done
    
    if [[ $reachable -eq ${#endpoints[@]} ]]; then
        record_test "AVD-GatewayConnectivity" "PASS" "All AVD endpoints reachable"
    elif [[ $reachable -gt 0 ]]; then
        record_test "AVD-GatewayConnectivity" "WARN" "$reachable/${#endpoints[@]} endpoints reachable"
    else
        record_test "AVD-GatewayConnectivity" "FAIL" "Cannot reach AVD endpoints"
    fi
}

test_storage_connectivity() {
    log TEST "Checking storage connectivity from session hosts..."
    
    local storage_name=$(az storage account list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -z "$storage_name" ]]; then
        record_test "Storage-Connectivity" "WARN" "No storage account to test"
        return
    fi
    
    local vm_name=$(az vm list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -z "$vm_name" ]]; then
        record_test "Storage-Connectivity" "WARN" "No VM to test from"
        return
    fi
    
    # Test SMB connectivity from VM
    local test_script='
        $result = Test-NetConnection -ComputerName "'$storage_name'.file.core.windows.net" -Port 445
        if ($result.TcpTestSucceeded) { "PASS" } else { "FAIL" }
    '
    
    local result=$(az vm run-command invoke --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" --command-id RunPowerShellScript \
        --scripts "$test_script" --query "value[0].message" -o tsv 2>&1)
    
    if echo "$result" | grep -q "PASS"; then
        record_test "Storage-Connectivity" "PASS" "SMB port 445 accessible from session host"
    else
        record_test "Storage-Connectivity" "FAIL" "Cannot reach storage on port 445"
    fi
}

#-------------------------------------------------------------------------------
# Identity Tests
#-------------------------------------------------------------------------------

test_entra_users() {
    log TEST "Checking Entra ID users..."
    
    local user_count=$(az ad user list --query "length([?contains(userPrincipalName, 'ph-consultant')])" -o tsv 2>/dev/null)
    
    if [[ -n "$user_count" && "$user_count" -gt 0 ]]; then
        record_test "EntraID-Users" "PASS" "$user_count AVD users found"
    else
        record_test "EntraID-Users" "WARN" "No AVD users found (may use different naming)"
    fi
}

test_entra_group() {
    log TEST "Checking Entra ID groups..."
    
    if az ad group show --group "TKT-Philippines-AVD-Users" &>/dev/null; then
        local member_count=$(az ad group member list --group "TKT-Philippines-AVD-Users" \
            --query "length(@)" -o tsv 2>/dev/null)
        record_test "EntraID-Group" "PASS" "AVD users group exists ($member_count members)"
    else
        record_test "EntraID-Group" "WARN" "AVD users group not found"
    fi
}

#-------------------------------------------------------------------------------
# FSLogix Tests
#-------------------------------------------------------------------------------

test_fslogix_configuration() {
    log TEST "Checking FSLogix configuration..."
    
    local vm_name=$(az vm list --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" -o tsv 2>/dev/null)
    
    if [[ -z "$vm_name" ]]; then
        record_test "FSLogix-Config" "WARN" "No VM to test"
        return
    fi
    
    local test_script='
        $result = @{
            Installed = Test-Path "C:\Program Files\FSLogix\Apps\frx.exe"
            Enabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -eq 1
            VHDLocation = (Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VHDLocations" -ErrorAction SilentlyContinue).VHDLocations
        }
        $result | ConvertTo-Json -Compress
    '
    
    local result=$(az vm run-command invoke --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" --command-id RunPowerShellScript \
        --scripts "$test_script" --query "value[0].message" -o tsv 2>&1)
    
    if echo "$result" | grep -q '"Installed":true'; then
        record_test "FSLogix-Installed" "PASS" "FSLogix agent installed"
    else
        record_test "FSLogix-Installed" "FAIL" "FSLogix not installed"
    fi
    
    if echo "$result" | grep -q '"Enabled":true'; then
        record_test "FSLogix-Enabled" "PASS" "Profile containers enabled"
    else
        record_test "FSLogix-Enabled" "WARN" "Profile containers not enabled (may need reboot)"
    fi
}

#-------------------------------------------------------------------------------
# Generate Report
#-------------------------------------------------------------------------------

generate_json_report() {
    local output_file="${OUTPUT_FILE:-/tmp/avd-validation-${TIMESTAMP}.json}"
    
    cat > "$output_file" << EOF
{
    "validation_report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "resource_group": "$RESOURCE_GROUP",
        "host_pool": "$HOST_POOL",
        "summary": {
            "total_tests": $((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED)),
            "passed": $TESTS_PASSED,
            "failed": $TESTS_FAILED,
            "warnings": $TESTS_WARNED,
            "status": "$(if [[ $TESTS_FAILED -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)"
        },
        "tests": {
EOF
    
    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        IFS='|' read -r status message <<< "${TEST_RESULTS[$test_name]}"
        
        if $first; then
            first=false
        else
            echo "," >> "$output_file"
        fi
        
        cat >> "$output_file" << EOF
            "$test_name": {
                "status": "$status",
                "message": "$message"
            }
EOF
    done
    
    cat >> "$output_file" << EOF
        }
    }
}
EOF
    
    log INFO "JSON report saved to: $output_file"
}

print_summary() {
    echo ""
    echo "============================================================"
    echo "  AVD Deployment Validation Summary"
    echo "============================================================"
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Host Pool:      $HOST_POOL"
    echo "  Timestamp:      $(date)"
    echo ""
    echo "  Results:"
    echo "    ${GREEN}✓ Passed:${NC}   $TESTS_PASSED"
    echo "    ${RED}✗ Failed:${NC}   $TESTS_FAILED"
    echo "    ${YELLOW}⚠ Warnings:${NC} $TESTS_WARNED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}Overall Status: PASSED${NC}"
        echo ""
        echo "  The AVD deployment appears healthy and ready for use."
    else
        echo -e "  ${RED}Overall Status: FAILED${NC}"
        echo ""
        echo "  Some tests failed. Please review the issues above."
    fi
    
    echo ""
    echo "  Log file: $LOG_FILE"
    echo "============================================================"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "============================================================"
    echo "  TKT Philippines AVD - Deployment Validation"
    echo "============================================================"
    echo ""
    
    parse_args "$@"
    
    log INFO "Starting validation for $RESOURCE_GROUP / $HOST_POOL"
    log INFO "Log file: $LOG_FILE"
    echo ""
    
    # Resource Tests
    echo "--- Resource Validation ---"
    test_resource_group
    test_virtual_network
    test_network_security_group
    test_storage_account
    test_log_analytics
    echo ""
    
    # AVD Service Tests
    echo "--- AVD Service Validation ---"
    test_avd_workspace
    test_avd_hostpool
    test_avd_application_group
    test_avd_session_hosts
    echo ""
    
    # Session Host Tests
    echo "--- Session Host Validation ---"
    test_session_host_vms
    test_session_host_extensions
    echo ""
    
    # Connectivity Tests
    echo "--- Connectivity Validation ---"
    test_avd_gateway_connectivity
    test_storage_connectivity
    echo ""
    
    # Identity Tests
    echo "--- Identity Validation ---"
    test_entra_users
    test_entra_group
    echo ""
    
    # FSLogix Tests
    echo "--- FSLogix Validation ---"
    test_fslogix_configuration
    echo ""
    
    # Generate reports
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        generate_json_report
    fi
    
    print_summary
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
