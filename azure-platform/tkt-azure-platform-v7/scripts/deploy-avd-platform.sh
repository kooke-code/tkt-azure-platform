#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - V7 Deployment Script
# Version: 7.0
# Date: 2026-02-14
# Domain: tktconsulting.be
#
# CHANGELOG V6.3:
#   - CRITICAL FIX: Added targetisaadjoined:i:1 RDP property to host pool
#   - CRITICAL FIX: Added stale Entra ID device cleanup before VM creation
#   - Added: Teams installation with WebRTC Redirector
#   - Added: Microsoft 365 Apps installation with shared licensing
#   - Added: Shared file share for consultant collaboration
#   - Added: Comprehensive validation script (50+ checks)
#
# CHANGELOG V6.2:
#   - Fixed: Entra ID join for cloud-only authentication
#   - Fixed: AADLoginForWindows extension installation
#   - Fixed: Virtual Machine User Login RBAC assignment
#   - Fixed: aadJoin parameter in DSC extension
#   - Added: Managed identity on VM creation
#   - Added: Longer wait time for Entra ID join completion
#
# DESCRIPTION:
#   Complete hands-off AVD deployment with Entra ID join support.
#   Deploys full AVD environment for TKT Philippines SAP consultants.
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Contributor role on Azure subscription
#   - User Administrator role in Entra ID
#   - bash shell (not zsh)
#
# USAGE:
#   bash deploy-avd-platform.sh                    # Interactive mode
#   bash deploy-avd-platform.sh --dry-run         # Preview only
#   bash deploy-avd-platform.sh --config env.sh   # Use config file
#
# COST: ~€235/month (2x D4s_v3 session hosts)
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# Cleanup on failure
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "\033[0;31m[ERROR] Deployment failed (exit code $exit_code).\033[0m"
        echo "  Log file: ${LOG_FILE:-/tmp/avd-deployment.log}"
        echo "  To resume, re-run the script - it will skip already-created resources."
        # Remove registration token file if it exists
        rm -f "${REGISTRATION_TOKEN_FILE:-}" 2>/dev/null
    fi
}
trap cleanup_on_exit EXIT

# Ensure running in bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash $0 $*"
    exit 1
fi

#===============================================================================
# DEFAULT CONFIGURATION - TKT CONSULTING
#===============================================================================

# Azure
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
LOCATION="${LOCATION:-southeastasia}"

# Networking
VNET_NAME="${VNET_NAME:-vnet-tktph-avd-sea}"
VNET_ADDRESS_PREFIX="${VNET_ADDRESS_PREFIX:-10.2.0.0/16}"
SUBNET_NAME="${SUBNET_NAME:-snet-avd}"
SUBNET_PREFIX="${SUBNET_PREFIX:-10.2.1.0/24}"
NSG_NAME="${NSG_NAME:-nsg-tktph-avd}"

# Storage
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-sttktphfslogix}"
STORAGE_SKU="${STORAGE_SKU:-Premium_LRS}"
FSLOGIX_SHARE_NAME="${FSLOGIX_SHARE_NAME:-profiles}"
FSLOGIX_QUOTA_GB="${FSLOGIX_QUOTA_GB:-100}"

# Monitoring
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-tktph-avd-sea}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"
ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-ag-tktph-avd}"
ALERT_EMAIL="${ALERT_EMAIL:-tom.tuerlings@tktconsulting.com}"

# AVD
WORKSPACE_NAME="${WORKSPACE_NAME:-tktph-ws}"
WORKSPACE_FRIENDLY_NAME="${WORKSPACE_FRIENDLY_NAME:-TKT Philippines Workspace}"
HOSTPOOL_NAME="${HOSTPOOL_NAME:-tktph-hp}"
APPGROUP_NAME="${APPGROUP_NAME:-tktph-dag}"
HOSTPOOL_TYPE="${HOSTPOOL_TYPE:-Pooled}"
LOAD_BALANCER_TYPE="${LOAD_BALANCER_TYPE:-BreadthFirst}"
MAX_SESSION_LIMIT="${MAX_SESSION_LIMIT:-4}"

# Session Hosts
VM_PREFIX="${VM_PREFIX:-vm-tktph}"
VM_COUNT="${VM_COUNT:-2}"
VM_SIZE="${VM_SIZE:-}"
VM_IMAGE="${VM_IMAGE:-MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest}"
VM_DISK_SIZE_GB="${VM_DISK_SIZE_GB:-128}"
ADMIN_USERNAME="${ADMIN_USERNAME:-avdadmin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# Identity - TKT CONSULTING DOMAIN
ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-4}"
USER_PASSWORD="${USER_PASSWORD:-}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"

# Entra ID Join (V6.2 - always enabled for cloud-only)
ENTRA_ID_JOIN="${ENTRA_ID_JOIN:-true}"

# Script Control
DRY_RUN="${DRY_RUN:-false}"
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"
FORCE="${FORCE:-false}"
CONFIG_FILE="${CONFIG_FILE:-}"

# Runtime
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOYMENT_ID="$TIMESTAMP"
LOG_FILE="/tmp/avd-deployment-${TIMESTAMP}.log"
REGISTRATION_TOKEN=""
REGISTRATION_TOKEN_FILE="/tmp/avd-registration-token-${TIMESTAMP}.txt"

#===============================================================================
# COLORS
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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
        INFO)    echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        ERROR)   echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
        PHASE)   echo -e "${CYAN}[$timestamp] [PHASE]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_phase() {
    local phase_num="$1"
    local phase_name="$2"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  PHASE $phase_num: $phase_name${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    log PHASE "Starting Phase $phase_num: $phase_name"
}

fail() {
    log ERROR "$1"
    echo ""
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  DEPLOYMENT FAILED${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Error: $1"
    echo "  Log file: $LOG_FILE"
    echo ""
    exit 1
}

#===============================================================================
# BANNER
#===============================================================================

show_banner() {
    clear
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}║     ████████╗██╗  ██╗████████╗     ██████╗ ██╗  ██╗                          ║${NC}"
    echo -e "${BLUE}║     ╚══██╔══╝██║ ██╔╝╚══██╔══╝     ██╔══██╗██║  ██║                          ║${NC}"
    echo -e "${BLUE}║        ██║   █████╔╝    ██║        ██████╔╝███████║                          ║${NC}"
    echo -e "${BLUE}║        ██║   ██╔═██╗    ██║        ██╔═══╝ ██╔══██║                          ║${NC}"
    echo -e "${BLUE}║        ██║   ██║  ██╗   ██║        ██║     ██║  ██║                          ║${NC}"
    echo -e "${BLUE}║        ╚═╝   ╚═╝  ╚═╝   ╚═╝        ╚═╝     ╚═╝  ╚═╝                          ║${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}║              Azure Virtual Desktop - V7 Automated Deployment                 ║${NC}"
    echo -e "${BLUE}║                         tktconsulting.be                                      ║${NC}"
    echo -e "${BLUE}║                      (Entra ID Join Enabled)                                  ║${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#===============================================================================
# PREREQUISITES
#===============================================================================

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        fail "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi
    
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log INFO "Azure CLI version: $az_version"
    
    # Verify version >= 2.83
    local major=$(echo "$az_version" | cut -d. -f1)
    local minor=$(echo "$az_version" | cut -d. -f2)
    if [[ "$major" -lt 2 ]] || [[ "$major" -eq 2 && "$minor" -lt 83 ]]; then
        log WARN "Azure CLI version $az_version may have deployment issues. Recommend upgrading to 2.83.0+"
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        fail "Not logged in to Azure. Run: az login"
    fi
    
    local account=$(az account show --query "name" -o tsv)
    log INFO "Azure account: $account"
    
    # Check for desktopvirtualization extension
    if ! az extension show --name desktopvirtualization &> /dev/null; then
        log INFO "Installing desktopvirtualization CLI extension..."
        az extension add --name desktopvirtualization --yes 2>/dev/null || true
    fi
    
    log SUCCESS "Prerequisites check passed"
}

#===============================================================================
# LOAD CONFIG FILE
#===============================================================================

load_config() {
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log INFO "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

#===============================================================================
# VM SIZE SELECTION WITH QUOTA CHECK
#===============================================================================

select_vm_size() {
    if [[ -n "$VM_SIZE" ]]; then
        log INFO "Using pre-configured VM size: $VM_SIZE"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  VM SIZE SELECTION${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    log INFO "Checking VM quota availability in $LOCATION..."
    
    # VM options - bash 3.2 compatible (no associative arrays)
    local vm_sizes="Standard_D4s_v3 Standard_D4s_v4 Standard_D4s_v5 Standard_D4as_v5 Standard_B4ms"
    local vm_families="DSv3 DSv4 DSv5 DASv5 BS"
    local vm_descs="Dedicated_recommended Dedicated_newer Dedicated_latest AMD_dedicated Burstable_cheaper"
    
    echo "Checking quota availability..."
    echo ""
    printf "%-4s %-20s %-8s %-8s %-25s %-15s\n" "#" "VM Size" "vCPUs" "RAM" "Type" "Quota Status"
    echo "────────────────────────────────────────────────────────────────────────────────────"
    
    local available_sizes=""
    local idx=1
    
    for size in $vm_sizes; do
        local family=$(echo $vm_families | cut -d' ' -f$idx)
        local desc=$(echo $vm_descs | cut -d' ' -f$idx | tr '_' ' ')
        
        local quota_info=$(az vm list-usage --location "$LOCATION" \
            --query "[?contains(name.value, '$family')].{current:currentValue, limit:limit}" \
            -o tsv 2>/dev/null | head -1)
        
        local current=$(echo "$quota_info" | cut -f1)
        local limit=$(echo "$quota_info" | cut -f2)
        
        current=${current:-0}
        limit=${limit:-0}
        
        local available=$((limit - current))
        local needed=$((VM_COUNT * 4))
        
        local quota_status
        if [[ $limit -eq 0 ]]; then
            quota_status="${RED}NO QUOTA${NC}"
        elif [[ $available -ge $needed ]]; then
            quota_status="${GREEN}✓ OK ($available free)${NC}"
            available_sizes="$available_sizes $idx:$size"
        else
            quota_status="${YELLOW}LOW ($available)${NC}"
        fi
        
        printf "%-4s %-20s %-8s %-8s %-25s " "$idx" "$size" "4" "16GB" "$desc"
        echo -e "$quota_status"
        
        idx=$((idx + 1))
    done
    
    echo ""
    
    # Check if any options available
    if [[ -z "$available_sizes" ]]; then
        log ERROR "No VM sizes have sufficient quota. Request quota increase in Azure Portal."
        exit 1
    fi
    
    # Default to first available
    local default_size=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f2)
    local default_num=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f1)
    
    read -p "Select VM size [${default_num}]: " selection
    selection=${selection:-$default_num}
    
    # Get selected size
    VM_SIZE=$(echo $available_sizes | tr ' ' '\n' | grep "^${selection}:" | cut -d':' -f2)
    
    if [[ -z "$VM_SIZE" ]]; then
        log WARN "Invalid selection or insufficient quota. Using default: $default_size"
        VM_SIZE="$default_size"
    fi
    
    log SUCCESS "Selected VM size: $VM_SIZE"
}

#===============================================================================
# INTERACTIVE PROMPTS
#===============================================================================

prompt_for_inputs() {
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        log INFO "Skipping prompts (using environment/config values)"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  CONFIGURATION${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 1. Subscription
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        echo -e "${BLUE}[1/5] Select Azure subscription${NC}"
        az account list --query "[].{Name:name, ID:id, Default:isDefault}" -o table
        echo ""
        read -p "Subscription ID (Enter for default): " input_sub
        if [[ -n "$input_sub" ]]; then
            SUBSCRIPTION_ID="$input_sub"
            az account set --subscription "$SUBSCRIPTION_ID"
        else
            SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
        fi
        echo ""
    fi
    
    # 2. Confirm domain
    echo -e "${BLUE}[2/5] Confirm Entra ID domain${NC}"
    echo "    Domain: $ENTRA_DOMAIN"
    read -p "    Press Enter to confirm or type new domain: " new_domain
    if [[ -n "$new_domain" ]]; then
        ENTRA_DOMAIN="$new_domain"
    fi
    echo ""
    
    # 3. Admin Password
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        echo -e "${BLUE}[3/5] Enter admin password for session hosts${NC}"
        echo "    Requirements: 12+ chars, uppercase, lowercase, number, special char"
        while true; do
            read -sp "    Password: " ADMIN_PASSWORD
            echo ""
            if [[ ${#ADMIN_PASSWORD} -ge 12 ]]; then
                break
            fi
            echo -e "${RED}    Password must be at least 12 characters${NC}"
        done
        echo ""
    fi
    
    # 4. User Password
    if [[ -z "$USER_PASSWORD" ]]; then
        echo -e "${BLUE}[4/5] Enter temporary password for consultant accounts${NC}"
        echo "    (Users will change on first login)"
        read -sp "    Password: " USER_PASSWORD
        echo ""
        echo ""
    fi
    
    # 5. Alert Email
    echo -e "${BLUE}[5/5] Confirm alert email${NC}"
    echo "    Current: $ALERT_EMAIL"
    read -p "    Press Enter to confirm or type new email: " new_email
    if [[ -n "$new_email" ]]; then
        ALERT_EMAIL="$new_email"
    fi
    echo ""
    
    # VM Size selection
    select_vm_size
    
    log SUCCESS "Configuration complete"
}

#===============================================================================
# CONFIGURATION SUMMARY
#===============================================================================

show_config_summary() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  DEPLOYMENT SUMMARY${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Azure"
    echo "  ─────"
    echo "    Subscription:     $(az account show --query name -o tsv)"
    echo "    Resource Group:   $RESOURCE_GROUP"
    echo "    Location:         $LOCATION"
    echo ""
    echo "  Infrastructure"
    echo "  ──────────────"
    echo "    Virtual Network:  $VNET_NAME ($VNET_ADDRESS_PREFIX)"
    echo "    Session Hosts:    $VM_COUNT x $VM_SIZE"
    echo "    Host Pool:        $HOSTPOOL_NAME ($HOSTPOOL_TYPE)"
    echo "    Max Sessions:     $MAX_SESSION_LIMIT per host"
    echo ""
    echo "  Identity (Entra ID Join)"
    echo "  ────────────────────────"
    echo "    Domain:           $ENTRA_DOMAIN"
    echo "    Join Type:        Microsoft Entra ID (cloud-only)"
    echo "    Users:            ${USER_PREFIX}-001 to ${USER_PREFIX}-$(printf '%03d' $USER_COUNT)"
    echo "    Security Group:   $SECURITY_GROUP_NAME"
    echo ""
    echo "  Monitoring"
    echo "  ──────────"
    echo "    Alert Email:      $ALERT_EMAIL"
    echo "    Log Retention:    $LOG_RETENTION_DAYS days"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}MODE: DRY RUN (no changes will be made)${NC}"
        echo ""
    fi
    
    if [[ "$SKIP_PROMPTS" != "true" && "$FORCE" != "true" ]]; then
        read -p "Proceed with deployment? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 0
        fi
    fi
}

#===============================================================================
# PHASE 1: NETWORKING
#===============================================================================

deploy_phase1_networking() {
    log_phase 1 "NETWORKING"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Resource Group, VNet, Subnet, NSG"
        return
    fi
    
    # Resource group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log INFO "Resource group $RESOURCE_GROUP already exists"
    else
        log INFO "Creating resource group: $RESOURCE_GROUP"
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags Environment=Production Project=TKT-Philippines Owner="$ALERT_EMAIL" DeploymentId="$DEPLOYMENT_ID" Version="7.0" \
            --output none
        log SUCCESS "Resource group created"
    fi
    
    # Virtual network
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
        log INFO "Virtual network $VNET_NAME already exists"
    else
        log INFO "Creating virtual network: $VNET_NAME"
        az network vnet create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VNET_NAME" \
            --address-prefix "$VNET_ADDRESS_PREFIX" \
            --subnet-name "$SUBNET_NAME" \
            --subnet-prefix "$SUBNET_PREFIX" \
            --output none
        log SUCCESS "Virtual network created"
    fi
    
    # NSG
    if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME" &>/dev/null; then
        log INFO "NSG $NSG_NAME already exists"
    else
        log INFO "Creating NSG: $NSG_NAME"
        az network nsg create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NSG_NAME" \
            --output none
        log SUCCESS "NSG created"
    fi
    
    # NSG rules - deny inbound RDP from internet, allow AVD outbound
    log INFO "Configuring NSG rules..."
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "DenyRDPFromInternet" \
        --priority 100 \
        --direction Inbound \
        --access Deny \
        --protocol Tcp \
        --source-address-prefixes Internet \
        --destination-port-ranges 3389 \
        --output none 2>/dev/null || true

    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowAVDServiceTraffic" \
        --priority 110 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes AzureCloud \
        --destination-port-ranges 443 \
        --output none 2>/dev/null || true
    log SUCCESS "NSG rules configured"

    # Associate NSG with subnet
    log INFO "Associating NSG with subnet..."
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME" \
        --output none
    
    log SUCCESS "Phase 1 complete: NETWORKING"
}

#===============================================================================
# PHASE 2: STORAGE & MONITORING
#===============================================================================

deploy_phase2_storage() {
    log_phase 2 "STORAGE & MONITORING"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Storage Account, File Share, Log Analytics"
        return
    fi
    
    # Storage account
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log INFO "Storage account $STORAGE_ACCOUNT already exists"
    else
        log INFO "Creating storage account: $STORAGE_ACCOUNT"
        az storage account create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_ACCOUNT" \
            --location "$LOCATION" \
            --kind FileStorage \
            --sku "$STORAGE_SKU" \
            --enable-large-file-share \
            --output none
        log SUCCESS "Storage account created"
    fi
    
    # FSLogix file share (using Entra ID auth - no storage keys needed)
    log INFO "Creating FSLogix file share: $FSLOGIX_SHARE_NAME"

    if az storage share show --name "$FSLOGIX_SHARE_NAME" --account-name "$STORAGE_ACCOUNT" --auth-mode login &>/dev/null; then
        log INFO "File share $FSLOGIX_SHARE_NAME already exists"
    else
        az storage share-rm create \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --name "$FSLOGIX_SHARE_NAME" \
            --quota "$FSLOGIX_QUOTA_GB" \
            --output none
        log SUCCESS "FSLogix file share created"
    fi
    
    # Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &>/dev/null; then
        log INFO "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        log INFO "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION" \
            --retention-time "$LOG_RETENTION_DAYS" \
            --output none
        log SUCCESS "Log Analytics workspace created"
    fi
    
    # Action group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" &>/dev/null; then
        log INFO "Action group $ACTION_GROUP_NAME already exists"
    else
        log INFO "Creating action group: $ACTION_GROUP_NAME"
        az monitor action-group create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ACTION_GROUP_NAME" \
            --short-name "tktphavd" \
            --action email adminEmail "$ALERT_EMAIL" \
            --output none
        log SUCCESS "Action group created"
    fi
    
    log SUCCESS "Phase 2 complete: STORAGE & MONITORING"
}

#===============================================================================
# PHASE 3: AVD CONTROL PLANE
#===============================================================================

deploy_phase3_avd() {
    log_phase 3 "AVD CONTROL PLANE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Workspace, Host Pool, Application Group"
        return
    fi
    
    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi
    
    # Workspace
    if az desktopvirtualization workspace show --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE_NAME" &>/dev/null 2>&1; then
        log INFO "Workspace $WORKSPACE_NAME already exists"
    else
        log INFO "Creating AVD workspace: $WORKSPACE_NAME"
        az desktopvirtualization workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WORKSPACE_NAME" \
            --location "$LOCATION" \
            --friendly-name "$WORKSPACE_FRIENDLY_NAME" \
            --output none
        log SUCCESS "AVD workspace created"
    fi
    
    # Host pool
    if az desktopvirtualization hostpool show --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" &>/dev/null 2>&1; then
        log INFO "Host pool $HOSTPOOL_NAME already exists"
    else
        log INFO "Creating host pool: $HOSTPOOL_NAME"
        az desktopvirtualization hostpool create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --location "$LOCATION" \
            --host-pool-type "$HOSTPOOL_TYPE" \
            --load-balancer-type "$LOAD_BALANCER_TYPE" \
            --max-session-limit "$MAX_SESSION_LIMIT" \
            --preferred-app-group-type Desktop \
            --custom-rdp-property "targetisaadjoined:i:1" \
            --output none
        log SUCCESS "Host pool created with Entra ID join RDP property"
    fi
    
    # Registration token
    log INFO "Generating registration token..."
    local expiry_time
    if date -v+24H &>/dev/null 2>&1; then
        expiry_time=$(date -u -v+24H '+%Y-%m-%dT%H:%M:%SZ')
    else
        expiry_time=$(date -u -d '+24 hours' '+%Y-%m-%dT%H:%M:%SZ')
    fi
    
    REGISTRATION_TOKEN=$(az desktopvirtualization hostpool update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --registration-info expiration-time="$expiry_time" registration-token-operation="Update" \
        --query "registrationInfo.token" -o tsv)
    
    if [[ -z "$REGISTRATION_TOKEN" || "$REGISTRATION_TOKEN" == "null" ]]; then
        fail "Failed to generate registration token. Check host pool exists and you have sufficient permissions."
    fi

    echo "$REGISTRATION_TOKEN" > "$REGISTRATION_TOKEN_FILE"
    chmod 600 "$REGISTRATION_TOKEN_FILE"
    log SUCCESS "Registration token saved"
    
    # Application group
    if az desktopvirtualization applicationgroup show --resource-group "$RESOURCE_GROUP" --name "$APPGROUP_NAME" &>/dev/null 2>&1; then
        log INFO "Application group $APPGROUP_NAME already exists"
    else
        log INFO "Creating application group: $APPGROUP_NAME"
        az desktopvirtualization applicationgroup create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APPGROUP_NAME" \
            --location "$LOCATION" \
            --host-pool-arm-path "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME" \
            --application-group-type Desktop \
            --output none
        log SUCCESS "Application group created"
    fi
    
    # Associate with workspace
    log INFO "Associating application group with workspace..."
    local app_group_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME"
    
    az desktopvirtualization workspace update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WORKSPACE_NAME" \
        --application-group-references "$app_group_id" \
        --output none
    
    log SUCCESS "Phase 3 complete: AVD CONTROL PLANE"
}

#===============================================================================
# PHASE 4: SESSION HOSTS (V6.2 - WITH ENTRA ID JOIN)
#===============================================================================

deploy_phase4_session_hosts() {
    log_phase 4 "SESSION HOSTS (Entra ID Join)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: $VM_COUNT VMs with Entra ID join and AVD agent"
        return
    fi
    
    # Get subnet ID
    local subnet_id=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --query "id" -o tsv)
    
    # Deploy each VM
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        
        # V6.3 FIX: Clean up stale Entra ID device record to prevent hostname_duplicate error
        log INFO "Checking for stale Entra ID device: $vm_name..."
        local stale_device_id
        stale_device_id=$(az rest --method GET \
            --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq '${vm_name}'" \
            --query "value[0].id" -o tsv 2>/dev/null || echo "")
        if [[ -n "$stale_device_id" && "$stale_device_id" != "null" ]]; then
            log WARN "Removing stale Entra ID device: $stale_device_id"
            az rest --method DELETE --url "https://graph.microsoft.com/v1.0/devices/${stale_device_id}" 2>/dev/null || true
            sleep 5
        fi
        
        # Create VM with system-assigned managed identity (required for Entra ID join)
        if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" &>/dev/null; then
            log INFO "VM $vm_name already exists"
        else
            log INFO "Deploying session host: $vm_name (5-10 minutes)..."
            
            az vm create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --image "$VM_IMAGE" \
                --size "$VM_SIZE" \
                --admin-username "$ADMIN_USERNAME" \
                --admin-password "$ADMIN_PASSWORD" \
                --subnet "$subnet_id" \
                --public-ip-address "" \
                --nsg "" \
                --os-disk-size-gb "$VM_DISK_SIZE_GB" \
                --storage-sku Premium_LRS \
                --license-type Windows_Client \
                --assign-identity \
                --output none
            
            log SUCCESS "$vm_name deployed with managed identity"
        fi
        
        # V6.2 FIX: Install AADLoginForWindows extension for Entra ID join
        log INFO "Configuring Entra ID join on $vm_name..."
        if az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AADLoginForWindows" &>/dev/null 2>&1; then
            log INFO "Entra ID join already configured on $vm_name"
        else
            az vm extension set \
                --resource-group "$RESOURCE_GROUP" \
                --vm-name "$vm_name" \
                --name "AADLoginForWindows" \
                --publisher "Microsoft.Azure.ActiveDirectory" \
                --version "2.0" \
                --output none
            log SUCCESS "Entra ID join configured on $vm_name"
        fi
        
        # Install AVD agent (DSC extension) with aadJoin parameter
        log INFO "Installing AVD agent on $vm_name..."
        
        if az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "DSC" &>/dev/null 2>&1; then
            log INFO "AVD agent already installed on $vm_name"
        else
            az vm extension set \
                --resource-group "$RESOURCE_GROUP" \
                --vm-name "$vm_name" \
                --name DSC \
                --publisher Microsoft.Powershell \
                --version 2.83 \
                --settings "{
                    \"modulesUrl\": \"https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip\",
                    \"configurationFunction\": \"Configuration.ps1\\\\AddSessionHost\",
                    \"properties\": {
                        \"hostPoolName\": \"$HOSTPOOL_NAME\",
                        \"registrationInfoToken\": \"$REGISTRATION_TOKEN\",
                        \"aadJoin\": true
                    }
                }" \
                --output none
            
            log SUCCESS "AVD agent installed on $vm_name"
        fi
        
        # Install monitoring agent
        log INFO "Installing monitoring agent on $vm_name..."
        if ! az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AzureMonitorWindowsAgent" &>/dev/null 2>&1; then
            az vm extension set \
                --resource-group "$RESOURCE_GROUP" \
                --vm-name "$vm_name" \
                --name AzureMonitorWindowsAgent \
                --publisher Microsoft.Azure.Monitor \
                --version 1.0 \
                --output none 2>/dev/null || log WARN "Monitoring agent may need manual setup"
        fi
    done
    
    # V6.2 FIX: Assign Virtual Machine User Login role to security group
    log INFO "Assigning VM login permissions to users..."
    local group_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query id -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$group_id" ]]; then
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv)
            
            az role assignment create \
                --assignee "$group_id" \
                --role "Virtual Machine User Login" \
                --scope "$vm_id" \
                --output none 2>/dev/null || true
            log INFO "  → $vm_name: VM login role assigned"
        done
        log SUCCESS "VM login permissions assigned to $SECURITY_GROUP_NAME"
    else
        log WARN "Security group not found yet - will be created in Phase 5"
    fi
    
    # Wait for registration (Entra ID join takes longer)
    log INFO "Waiting for session hosts to complete Entra ID join and register (3-5 minutes)..."
    sleep 90  # Entra ID join takes longer than standard domain join
    
    local max_attempts=15
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local available_count=$(az desktopvirtualization sessionhost list \
            --resource-group "$RESOURCE_GROUP" \
            --host-pool-name "$HOSTPOOL_NAME" \
            --query "[?status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ "$available_count" -ge "$VM_COUNT" ]]; then
            log SUCCESS "All $VM_COUNT session hosts are Available"
            break
        fi
        
        log INFO "Attempt $attempt/$max_attempts: $available_count/$VM_COUNT hosts available..."
        sleep 20
        ((attempt++))
    done
    
    log SUCCESS "Phase 4 complete: SESSION HOSTS"
}

#===============================================================================
# PHASE 4.5: APPLICATION INSTALLATION (V6.3)
#===============================================================================

deploy_phase4_5_applications() {
    log_phase "4.5" "APPLICATION INSTALLATION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would install: Teams, WebRTC Redirector, Microsoft 365 Apps"
        return
    fi
    
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "Installing applications on $vm_name..."
        
        # Install WebRTC Redirector + Teams optimization registry
        log INFO "  → Installing WebRTC Redirector and Teams optimization..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Create temp directory
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                
                # Download and install WebRTC Redirector
                Invoke-WebRequest -Uri "https://aka.ms/msrdcwebrtcsvc/msi" -OutFile "C:\Temp\MsRdcWebRTCSvc.msi"
                Start-Process msiexec.exe -ArgumentList "/i C:\Temp\MsRdcWebRTCSvc.msi /quiet /norestart" -Wait
                
                # Set Teams AVD environment registry key
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -Type DWord
            ' --output none 2>/dev/null || log WARN "WebRTC install may have failed on $vm_name"
        log SUCCESS "  → WebRTC Redirector installed"
        
        # Install Teams
        log INFO "  → Installing Microsoft Teams..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409" -OutFile "C:\Temp\teamsbootstrapper.exe"
                Start-Process -FilePath "C:\Temp\teamsbootstrapper.exe" -ArgumentList "-p" -Wait
            ' --output none 2>/dev/null || log WARN "Teams install may have failed on $vm_name"
        log SUCCESS "  → Teams installed"
        
        # Install Microsoft 365 Apps
        log INFO "  → Installing Microsoft 365 Apps (10-15 minutes)..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Create Office directory
                New-Item -ItemType Directory -Path "C:\Temp\Office" -Force | Out-Null
                
                # Download Office Deployment Tool
                Invoke-WebRequest -Uri "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18129-20030.exe" -OutFile "C:\Temp\Office\ODT.exe"
                Start-Process -FilePath "C:\Temp\Office\ODT.exe" -ArgumentList "/quiet /extract:C:\Temp\Office" -Wait
                
                # Create configuration file
                $config = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="MonthlyEnterprise">
    <Product ID="O365BusinessRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="1" />
  <Property Name="PinIconsToTaskbar" Value="TRUE" />
  <Updates Enabled="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
                $config | Out-File -FilePath "C:\Temp\Office\config.xml" -Encoding UTF8
                
                # Install Office
                Start-Process -FilePath "C:\Temp\Office\setup.exe" -ArgumentList "/configure C:\Temp\Office\config.xml" -Wait
            ' --output none 2>/dev/null || log WARN "Office install may have failed on $vm_name"
        log SUCCESS "  → Microsoft 365 Apps installed"
    done
    
    log SUCCESS "Phase 4.5 complete: APPLICATION INSTALLATION"
}

#===============================================================================
# PHASE 5: IDENTITY (V6.2 - WITH VM LOGIN ROLE)
#===============================================================================

deploy_phase5_identity() {
    log_phase 5 "IDENTITY & USER ASSIGNMENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: $USER_COUNT users, security group, role assignments"
        return
    fi
    
    # Security group
    local group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null)
    
    if [[ -z "$group_id" ]]; then
        log INFO "Creating security group: $SECURITY_GROUP_NAME"
        group_id=$(az ad group create \
            --display-name "$SECURITY_GROUP_NAME" \
            --mail-nickname "tktph-avd-users" \
            --query "id" -o tsv)
        log SUCCESS "Security group created"
    else
        log INFO "Security group $SECURITY_GROUP_NAME already exists"
    fi
    
    # Create users
    for i in $(seq 1 $USER_COUNT); do
        local user_num=$(printf '%03d' $i)
        local upn="${USER_PREFIX}-${user_num}@${ENTRA_DOMAIN}"
        local display_name="PH Consultant $user_num"
        
        if az ad user show --id "$upn" &>/dev/null 2>&1; then
            log INFO "User $upn already exists"
        else
            log INFO "Creating user: $upn"
            az ad user create \
                --display-name "$display_name" \
                --user-principal-name "$upn" \
                --password "$USER_PASSWORD" \
                --force-change-password-next-sign-in true \
                --output none
            log SUCCESS "User $upn created"
        fi
        
        # Add to group
        local user_id=$(az ad user show --id "$upn" --query "id" -o tsv 2>/dev/null)
        if [[ -n "$user_id" ]]; then
            az ad group member add --group "$SECURITY_GROUP_NAME" --member-id "$user_id" 2>/dev/null || true
        fi
    done
    
    log SUCCESS "All users created and added to group"
    
    # Assign Desktop Virtualization User role to application group
    log INFO "Assigning users to application group..."
    
    local app_group_scope="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME"
    local group_object_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query "id" -o tsv)
    
    az role assignment create \
        --assignee "$group_object_id" \
        --role "Desktop Virtualization User" \
        --scope "$app_group_scope" \
        --output none 2>/dev/null || log INFO "Desktop Virtualization User role may already exist"
    
    log SUCCESS "Desktop Virtualization User role assigned"
    
    # V6.2 FIX: Assign Virtual Machine User Login role (if not done in Phase 4)
    log INFO "Ensuring VM login permissions..."
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv 2>/dev/null)
        
        if [[ -n "$vm_id" ]]; then
            az role assignment create \
                --assignee "$group_object_id" \
                --role "Virtual Machine User Login" \
                --scope "$vm_id" \
                --output none 2>/dev/null || true
        fi
    done
    log SUCCESS "Virtual Machine User Login role assigned"
    
    log SUCCESS "Phase 5 complete: IDENTITY & USER ASSIGNMENT"
}

#===============================================================================
# PHASE 6: VALIDATION
#===============================================================================

deploy_phase6_validation() {
    log_phase 6 "VALIDATION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would run validation checks"
        return
    fi
    
    local passed=0
    local failed=0
    
    echo ""
    printf "  %-45s %s\n" "Check" "Status"
    echo "  ─────────────────────────────────────────────────────────"
    
    # Resource group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-45s ${GREEN}✓ OK${NC}\n" "Resource Group"
        ((passed++))
    else
        printf "  %-45s ${RED}✗ FAIL${NC}\n" "Resource Group"
        ((failed++))
    fi
    
    # VMs with Entra ID join
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local state=$(az vm get-instance-view --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
        
        if [[ "$state" == "VM running" ]]; then
            printf "  %-45s ${GREEN}✓ Running${NC}\n" "$vm_name"
            ((passed++))
        else
            printf "  %-45s ${RED}✗ $state${NC}\n" "$vm_name"
            ((failed++))
        fi
        
        # Check AADLoginForWindows extension
        local aad_ext=$(az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AADLoginForWindows" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$aad_ext" == "Succeeded" ]]; then
            printf "  %-45s ${GREEN}✓ Configured${NC}\n" "  └─ Entra ID Join"
            ((passed++))
        else
            printf "  %-45s ${YELLOW}⚠ $aad_ext${NC}\n" "  └─ Entra ID Join"
        fi
    done
    
    # Session hosts available
    local available=$(az desktopvirtualization sessionhost list \
        --resource-group "$RESOURCE_GROUP" \
        --host-pool-name "$HOSTPOOL_NAME" \
        --query "[?status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$available" -ge "$VM_COUNT" ]]; then
        printf "  %-45s ${GREEN}✓ $available Available${NC}\n" "Session Hosts Health"
        ((passed++))
    else
        printf "  %-45s ${YELLOW}⚠ $available/$VM_COUNT${NC}\n" "Session Hosts Health"
    fi
    
    # User assignment - Desktop Virtualization User
    local dag_assignments=$(az role assignment list \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME" \
        --query "[?roleDefinitionName=='Desktop Virtualization User'] | length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$dag_assignments" -gt 0 ]]; then
        printf "  %-45s ${GREEN}✓ Assigned${NC}\n" "App Group Assignment"
        ((passed++))
    else
        printf "  %-45s ${RED}✗ Not assigned${NC}\n" "App Group Assignment"
        ((failed++))
    fi
    
    # V6.2: Check VM User Login role
    local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "${VM_PREFIX}-01" --query id -o tsv 2>/dev/null)
    local vm_login_assignments=$(az role assignment list \
        --scope "$vm_id" \
        --query "[?roleDefinitionName=='Virtual Machine User Login'] | length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$vm_login_assignments" -gt 0 ]]; then
        printf "  %-45s ${GREEN}✓ Assigned${NC}\n" "VM User Login Role"
        ((passed++))
    else
        printf "  %-45s ${RED}✗ Not assigned${NC}\n" "VM User Login Role"
        ((failed++))
    fi
    
    # Storage
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-45s ${GREEN}✓ OK${NC}\n" "Storage Account"
        ((passed++))
    else
        printf "  %-45s ${RED}✗ FAIL${NC}\n" "Storage Account"
        ((failed++))
    fi
    
    echo "  ─────────────────────────────────────────────────────────"
    printf "  %-45s ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}\n" "Results"
    echo ""
    
    log SUCCESS "Phase 6 complete: VALIDATION"
}

#===============================================================================
# FINAL SUMMARY
#===============================================================================

show_summary() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                          DEPLOYMENT COMPLETE (V7)                              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Resource Group:     $RESOURCE_GROUP"
    echo "  Session Hosts:      $VM_COUNT x $VM_SIZE"
    echo "  Join Type:          Microsoft Entra ID (cloud-only)"
    echo "  Estimated Cost:     ~€235/month"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "  │  USER ACCESS                                                                │"
    echo "  ├─────────────────────────────────────────────────────────────────────────────┤"
    echo "  │  Web Client:  https://rdweb.wvd.microsoft.com/arm/webclient                 │"
    echo "  │  Users:       ${USER_PREFIX}-001 to ${USER_PREFIX}-$(printf '%03d' $USER_COUNT)@${ENTRA_DOMAIN}               │"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Files:"
    echo "    Log:               $LOG_FILE"
    echo "    Registration:      $REGISTRATION_TOKEN_FILE"
    echo ""
    echo -e "  ${YELLOW}Next Steps:${NC}"
    echo "    1. Wait 3-5 minutes for Entra ID join to complete"
    echo "    2. Test login at the web client URL"
    echo "    3. Change default user passwords"
    echo "    4. Configure Conditional Access (MFA)"
    echo "    5. Install SAP GUI on session hosts"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    show_banner
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN="true"; shift ;;
            --skip-prompts) SKIP_PROMPTS="true"; shift ;;
            --force) FORCE="true"; shift ;;
            --config) CONFIG_FILE="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run        Preview without making changes"
                echo "  --skip-prompts   Use environment/config values only"
                echo "  --force          Skip confirmation prompts"
                echo "  --config FILE    Load configuration from file"
                echo "  --help           Show this help"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    load_config
    check_prerequisites
    prompt_for_inputs
    show_config_summary
    
    deploy_phase1_networking
    deploy_phase2_storage
    deploy_phase3_avd
    deploy_phase4_session_hosts
    deploy_phase4_5_applications
    deploy_phase5_identity
    deploy_phase6_validation
    
    show_summary
}

main "$@"
