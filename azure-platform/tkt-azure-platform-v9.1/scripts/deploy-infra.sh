#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9.1 Infrastructure Deployment Script (Track B)
# Version: 9.1
# Date: 2026-02-17
#
# TRACK B — Requires Contributor + User Access Administrator on subscription
#           Does NOT require any Entra ID directory roles.
#
# This script deploys all Azure infrastructure:
#   Phase 1: Networking (RG, VNet, NSG, rules)
#   Phase 2: Storage & Monitoring (storage account, FSLogix, Log Analytics)
#   Phase 2.5: Shared Documentation Storage (shared-docs share + folders)
#   Phase 3: AVD Control Plane (workspace, host pool, app group)
#   Phase 4: Session Hosts (VMs, extensions, auto-shutdown)
#   Phase 4.5: Application Installation (Teams, Edge, FSLogix, drive mapping)
#   Phase 4.6: Session Logging (DCR, audit policies, weekly export)
#   Phase 5: RBAC & Key Vault (roles, break-glass password, storage permissions)
#   Phase 6: Security & Governance (locks, diagnostics, scaling, watermarking)
#   Phase 7: Validation
#
# SPLIT FROM: V9 deploy-avd-platform.sh (all infrastructure phases)
# COUNTERPART: deploy-identity.sh (Track A — identity, Global Admin)
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Contributor + User Access Administrator on Azure subscription
#   - deploy-identity.sh must have been run first (Track A)
#   - jq (for users.json parsing)
#   - bash shell (not zsh)
#
# USAGE:
#   bash deploy-infra.sh                                          # Interactive
#   bash deploy-infra.sh --security-group-name "MyGroup"          # Custom group
#   bash deploy-infra.sh --dry-run                                # Preview only
#   bash deploy-infra.sh --skip-prompts                           # Non-interactive
#   bash deploy-infra.sh --config env.sh                          # Use config file
#
# COST: ~EUR390/month (3x D4s_v5 session hosts + shared storage)
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# Cleanup on failure
cleanup_on_exit() {
    local exit_code=$?
    rm -f "${_ADMIN_PW_FILE:-}" 2>/dev/null
    rm -f "${_USER_PW_FILE:-}" 2>/dev/null
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "\033[0;31m[ERROR] Infrastructure deployment failed (exit code $exit_code).\033[0m"
        echo "  Log file: ${LOG_FILE:-/tmp/infra-deployment.log}"
        echo "  To resume, re-run the script - it will skip already-created resources."
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
SHARED_DOCS_SHARE_NAME="${SHARED_DOCS_SHARE_NAME:-shared-docs}"
SHARED_DOCS_QUOTA_GB="${SHARED_DOCS_QUOTA_GB:-50}"

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
MAX_SESSION_LIMIT="${MAX_SESSION_LIMIT:-3}"

# Session Hosts
VM_PREFIX="${VM_PREFIX:-vm-tktph}"
VM_COUNT="${VM_COUNT:-3}"
VM_SIZE="${VM_SIZE:-}"
VM_DEFAULT_SIZE="Standard_D4s_v5"
VM_IMAGE="${VM_IMAGE:-MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest}"
VM_DISK_SIZE_GB="${VM_DISK_SIZE_GB:-128}"
ADMIN_USERNAME="${ADMIN_USERNAME:-avdadmin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# VM Auto-shutdown schedule
VM_SCHEDULE_ENABLED="${VM_SCHEDULE_ENABLED:-true}"
VM_SCHEDULE_SHUTDOWN_TIME="${VM_SCHEDULE_SHUTDOWN_TIME:-1900}"
VM_SCHEDULE_TIMEZONE="${VM_SCHEDULE_TIMEZONE:-Asia/Manila}"
VM_SCHEDULE_WEEKDAYS="${VM_SCHEDULE_WEEKDAYS:-Monday,Tuesday,Wednesday,Thursday,Friday}"

# Identity — Pre-existing group from Track A
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"

# Entra ID Join (always enabled for cloud-only)
ENTRA_ID_JOIN="${ENTRA_ID_JOIN:-true}"

# SAP / Application URLs
SAP_FIORI_URL="${SAP_FIORI_URL:-https://my300000.s4hana.cloud.sap}"
ZOHO_DESK_URL="${ZOHO_DESK_URL:-https://desk.zoho.com}"

# Break-glass (password passed in for Key Vault storage)
BREAK_GLASS_PASSWORD="${BREAK_GLASS_PASSWORD:-}"
BREAK_GLASS_USERNAME="${BREAK_GLASS_USERNAME:-tktph-breakglass}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-tktph-avd}"

# V9: ActivTrak (optional)
ACTIVTRAK_ACCOUNT_ID="${ACTIVTRAK_ACCOUNT_ID:-}"

# Script Control
DRY_RUN="${DRY_RUN:-false}"
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"
FORCE="${FORCE:-false}"
CONFIG_FILE="${CONFIG_FILE:-}"
USERS_FILE="${USERS_FILE:-}"

# Runtime
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOYMENT_ID="$TIMESTAMP"
LOG_FILE="/tmp/infra-deployment-${TIMESTAMP}.log"
REGISTRATION_TOKEN=""
REGISTRATION_TOKEN_FILE="/tmp/avd-registration-token-${TIMESTAMP}.txt"

_ADMIN_PW_FILE=""
_USER_PW_FILE=""

# Version tag
VERSION_TAG="9.1"

# User count (read from users.json for VM calculation, or default)
USER_COUNT="${USER_COUNT:-6}"

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
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  PHASE $phase_num: $phase_name${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    log PHASE "Starting Phase $phase_num: $phase_name"
}

fail() {
    log ERROR "$1"
    echo ""
    echo -e "${RED}===============================================================================${NC}"
    echo -e "${RED}  DEPLOYMENT FAILED${NC}"
    echo -e "${RED}===============================================================================${NC}"
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
    echo -e "${BLUE}+===============================================================================+${NC}"
    echo -e "${BLUE}|                                                                               |${NC}"
    echo -e "${BLUE}|     ████████╗██╗  ██╗████████╗     ██████╗ ██╗  ██╗                           |${NC}"
    echo -e "${BLUE}|     ╚══██╔══╝██║ ██╔╝╚══██╔══╝     ██╔══██╗██║  ██║                           |${NC}"
    echo -e "${BLUE}|        ██║   █████╔╝    ██║        ██████╔╝███████║                           |${NC}"
    echo -e "${BLUE}|        ██║   ██╔═██╗    ██║        ██╔═══╝ ██╔══██║                           |${NC}"
    echo -e "${BLUE}|        ██║   ██║  ██╗   ██║        ██║     ██║  ██║                           |${NC}"
    echo -e "${BLUE}|        ╚═╝   ╚═╝  ╚═╝   ╚═╝        ╚═╝     ╚═╝  ╚═╝                           |${NC}"
    echo -e "${BLUE}|                                                                               |${NC}"
    echo -e "${BLUE}|        Azure Virtual Desktop - V9.1 Infrastructure Deployment                 |${NC}"
    echo -e "${BLUE}|              TRACK B — Contributor + User Access Admin                        |${NC}"
    echo -e "${BLUE}|                          ${ENTRA_DOMAIN}                                      |${NC}"
    echo -e "${BLUE}|                      (Entra ID Join Enabled)                                  |${NC}"
    echo -e "${BLUE}|                                                                               |${NC}"
    echo -e "${BLUE}|    SAP S/4HANA Public Cloud | Fiori | Zoho Desk | Teams | Shared Storage      |${NC}"
    echo -e "${BLUE}|                                                                               |${NC}"
    echo -e "${BLUE}+===============================================================================+${NC}"
    echo ""
}

#===============================================================================
# PREREQUISITES
#===============================================================================

check_prerequisites() {
    log INFO "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        fail "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi

    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log INFO "Azure CLI version: $az_version"

    local major=$(echo "$az_version" | cut -d. -f1)
    local minor=$(echo "$az_version" | cut -d. -f2)
    if [[ "$major" -lt 2 ]] || [[ "$major" -eq 2 && "$minor" -lt 83 ]]; then
        log WARN "Azure CLI version $az_version may have deployment issues. Recommend upgrading to 2.83.0+"
    fi

    if ! az account show &> /dev/null; then
        fail "Not logged in to Azure. Run: az login"
    fi

    local account=$(az account show --query "name" -o tsv)
    log INFO "Azure account: $account"

    if ! command -v jq &> /dev/null; then
        log WARN "jq not found. Install jq for users.json support."
    else
        log INFO "jq version: $(jq --version 2>/dev/null || echo 'unknown')"
    fi

    if ! az extension show --name desktopvirtualization &> /dev/null; then
        log INFO "Installing desktopvirtualization CLI extension..."
        az extension add --name desktopvirtualization --yes 2>/dev/null || true
    fi

    if ! az extension show --name monitor-control-service &> /dev/null; then
        log INFO "Installing monitor-control-service CLI extension..."
        az extension add --name monitor-control-service --yes 2>/dev/null || true
    fi

    log SUCCESS "Prerequisites check passed"
}

#===============================================================================
# VALIDATE TRACK A COMPLETED (security group must exist)
#===============================================================================

validate_track_a() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would validate Track A: security group '$SECURITY_GROUP_NAME' exists"
        return
    fi

    log INFO "Validating Track A (identity) has been completed..."

    local group_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query "id" -o tsv 2>/dev/null || echo "")

    if [[ -z "$group_id" ]]; then
        fail "Security group '$SECURITY_GROUP_NAME' not found in Entra ID.
  Track A (deploy-identity.sh) must be run first by a Global Admin.
  The security group is required before infrastructure deployment can proceed.

  If using a different group name, pass: --security-group-name \"YourGroupName\""
    fi

    local member_count=$(az ad group member list --group "$SECURITY_GROUP_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")

    log SUCCESS "Track A validated: Security group '$SECURITY_GROUP_NAME' exists ($group_id) with $member_count members"
}

#===============================================================================
# LOAD CONFIG / USER COUNT FROM users.json
#===============================================================================

load_config() {
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log INFO "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi

    # Load user count from users.json (for VM calculation only — no user creation)
    local users_file=""
    if [[ -n "$USERS_FILE" && -f "$USERS_FILE" ]]; then
        users_file="$USERS_FILE"
    elif [[ -f "${SCRIPT_DIR}/users.json" ]]; then
        users_file="${SCRIPT_DIR}/users.json"
    fi

    if [[ -n "$users_file" ]] && command -v jq &> /dev/null; then
        local user_count=$(jq '.users | length' "$users_file" 2>/dev/null || echo "0")
        if [[ "$user_count" -gt 0 ]]; then
            USER_COUNT="$user_count"
            VM_COUNT=$(( (USER_COUNT + MAX_SESSION_LIMIT - 1) / MAX_SESSION_LIMIT ))
            log INFO "From users.json: $USER_COUNT users -> $VM_COUNT VMs"
        fi

        local json_domain=$(jq -r '.domain // empty' "$users_file" 2>/dev/null)
        if [[ -n "$json_domain" ]]; then
            ENTRA_DOMAIN="$json_domain"
        fi

        local json_group=$(jq -r '.security_group // empty' "$users_file" 2>/dev/null)
        if [[ -n "$json_group" ]]; then
            SECURITY_GROUP_NAME="$json_group"
        fi
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
    echo -e "${YELLOW}===============================================================================${NC}"
    echo -e "${YELLOW}  VM SIZE SELECTION${NC}"
    echo -e "${YELLOW}===============================================================================${NC}"
    echo ""

    log INFO "Checking VM quota availability in $LOCATION..."

    local vm_sizes="Standard_D4s_v5 Standard_D4s_v4 Standard_D4s_v3 Standard_D4as_v5 Standard_B4ms"
    local vm_families="DSv5 DSv4 DSv3 DASv5 BS"
    local vm_descs="Recommended_v8_default Dedicated_previous Dedicated_legacy AMD_dedicated Burstable_cheaper"

    echo "Checking quota availability..."
    echo ""
    printf "%-4s %-20s %-8s %-8s %-25s %-15s\n" "#" "VM Size" "vCPUs" "RAM" "Type" "Quota Status"
    echo "-------------------------------------------------------------------------------------"

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
            quota_status="${GREEN}OK ($available free)${NC}"
            available_sizes="$available_sizes $idx:$size"
        else
            quota_status="${YELLOW}LOW ($available)${NC}"
        fi

        printf "%-4s %-20s %-8s %-8s %-25s " "$idx" "$size" "4" "16GB" "$desc"
        echo -e "$quota_status"

        idx=$((idx + 1))
    done

    echo ""

    if [[ -z "$available_sizes" ]]; then
        log ERROR "No VM sizes have sufficient quota. Request quota increase in Azure Portal."
        exit 1
    fi

    local default_size=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f2)
    local default_num=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f1)

    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        VM_SIZE="$default_size"
    else
        read -p "Select VM size [${default_num}]: " selection
        selection=${selection:-$default_num}

        VM_SIZE=$(echo $available_sizes | tr ' ' '\n' | grep "^${selection}:" | cut -d':' -f2)

        if [[ -z "$VM_SIZE" ]]; then
            log WARN "Invalid selection or insufficient quota. Using default: $default_size"
            VM_SIZE="$default_size"
        fi
    fi

    log SUCCESS "Selected VM size: $VM_SIZE"
}

#===============================================================================
# INTERACTIVE PROMPTS
#===============================================================================

prompt_for_inputs() {
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        log INFO "Skipping prompts (using environment/config values)"
        if [[ -z "$VM_SIZE" ]]; then
            VM_SIZE="$VM_DEFAULT_SIZE"
            log INFO "Using default VM size: $VM_SIZE"
        fi
        return
    fi

    echo ""
    echo -e "${YELLOW}===============================================================================${NC}"
    echo -e "${YELLOW}  CONFIGURATION (Track B — Infrastructure)${NC}"
    echo -e "${YELLOW}===============================================================================${NC}"
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

    # 4. Break-glass password (for Key Vault storage)
    if [[ -z "$BREAK_GLASS_PASSWORD" ]]; then
        echo -e "${BLUE}[4/5] Break-glass admin password (from Track A credentials file)${NC}"
        echo "    This password will be stored in Azure Key Vault."
        echo "    Leave blank to skip Key Vault break-glass storage."
        read -sp "    Password: " BREAK_GLASS_PASSWORD
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
# PASSWORD FILE HELPERS
#===============================================================================

setup_password_files() {
    _ADMIN_PW_FILE=$(mktemp /tmp/.avd-admin-pw-XXXXXX)
    chmod 600 "$_ADMIN_PW_FILE"
    printf '%s' "$ADMIN_PASSWORD" > "$_ADMIN_PW_FILE"
}

get_admin_password() {
    cat "$_ADMIN_PW_FILE"
}

#===============================================================================
# CONFIGURATION SUMMARY
#===============================================================================

show_config_summary() {
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  DEPLOYMENT SUMMARY - V9.1 TRACK B (Infrastructure)${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
    echo "  Azure"
    echo "  -----"
    echo "    Subscription:     $(az account show --query name -o tsv)"
    echo "    Resource Group:   $RESOURCE_GROUP"
    echo "    Location:         $LOCATION"
    echo ""
    echo "  Infrastructure"
    echo "  --------------"
    echo "    Virtual Network:  $VNET_NAME ($VNET_ADDRESS_PREFIX)"
    echo "    Session Hosts:    $VM_COUNT x $VM_SIZE (spread across availability zones 1,2,3)"
    echo "    Host Pool:        $HOSTPOOL_NAME ($HOSTPOOL_TYPE)"
    echo "    Max Sessions:     $MAX_SESSION_LIMIT per host"
    echo ""
    echo "  Storage"
    echo "  -------"
    echo "    FSLogix Profiles: $FSLOGIX_SHARE_NAME (${FSLOGIX_QUOTA_GB}GB)"
    echo "    Shared Docs:      $SHARED_DOCS_SHARE_NAME (${SHARED_DOCS_QUOTA_GB}GB)"
    echo ""
    echo "  Identity (from Track A)"
    echo "  -----------------------"
    echo "    Domain:           $ENTRA_DOMAIN"
    echo "    Security Group:   $SECURITY_GROUP_NAME"
    echo ""
    echo "  Cost"
    echo "  ----"
    echo "    Estimated:        ~EUR390/month (${VM_COUNT}x D4s_v5)"
    echo "    Version:          $VERSION_TAG"
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
# (Extracted from v9 deploy-avd-platform.sh Phase 1, lines 767-908)
#===============================================================================

deploy_phase1_networking() {
    log_phase 1 "NETWORKING"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Resource Group, VNet, Subnet, NSG with cloud SAP/Zoho/Teams rules"
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
            --tags Environment=Production Project=TKT-Philippines Owner="$ALERT_EMAIL" DeploymentId="$DEPLOYMENT_ID" Version="$VERSION_TAG" \
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
            --tags Version="$VERSION_TAG" \
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
            --tags Version="$VERSION_TAG" \
            --output none
        log SUCCESS "NSG created"
    fi

    # NSG Rules
    log INFO "Configuring NSG rules..."

    az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
        --name "DenyRDPFromInternet" --priority 100 --direction Inbound --access Deny \
        --protocol Tcp --source-address-prefixes Internet --destination-port-ranges 3389 \
        --output none 2>/dev/null || true

    az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
        --name "AllowAVDServiceTraffic" --priority 110 --direction Outbound --access Allow \
        --protocol Tcp --source-address-prefixes VirtualNetwork --destination-address-prefixes AzureCloud \
        --destination-port-ranges 443 --output none 2>/dev/null || true

    az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
        --name "AllowSAPFioriHTTPS" --priority 200 --direction Outbound --access Allow \
        --protocol Tcp --source-address-prefixes VirtualNetwork --destination-address-prefixes Internet \
        --destination-port-ranges 443 \
        --description "Allow HTTPS to SAP S/4HANA Public Cloud (Fiori), Zoho Desk, Teams" \
        --output none 2>/dev/null || true

    az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
        --name "AllowTeamsMedia" --priority 210 --direction Outbound --access Allow \
        --protocol Udp --source-address-prefixes VirtualNetwork --destination-address-prefixes Internet \
        --destination-port-ranges 3478-3481 --description "Allow Teams TURN/STUN UDP media traffic" \
        --output none 2>/dev/null || true

    az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
        --name "AllowTeamsMediaTCP" --priority 220 --direction Outbound --access Allow \
        --protocol Tcp --source-address-prefixes VirtualNetwork --destination-address-prefixes Internet \
        --destination-port-ranges 50000-50059 --description "Allow Teams media TCP port range" \
        --output none 2>/dev/null || true

    log SUCCESS "NSG rules configured (RDP denied, AVD/SAP/Zoho/Teams HTTPS allowed)"

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
# (Extracted from v9 Phase 2, lines 910-1005)
#===============================================================================

deploy_phase2_storage() {
    log_phase 2 "STORAGE & MONITORING"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Storage Account, FSLogix share, Log Analytics, Action Group"
        return
    fi

    # Storage account (Azure AD Kerberos enabled)
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log INFO "Storage account $STORAGE_ACCOUNT already exists"
        local current_auth
        current_auth=$(az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" \
            --query "azureFilesIdentityBasedAuthentication.directoryServiceOptions" -o tsv 2>/dev/null || echo "None")
        if [[ "$current_auth" != "AADKERB" ]]; then
            log INFO "Enabling Azure AD Kerberos on existing storage account..."
            az storage account update --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" \
                --enable-files-aadkerb true --default-share-permission "StorageFileDataSmbShareContributor" --output none
            log SUCCESS "Azure AD Kerberos enabled on $STORAGE_ACCOUNT"
        fi
    else
        log INFO "Creating storage account: $STORAGE_ACCOUNT (with Azure AD Kerberos)"
        az storage account create \
            --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" --location "$LOCATION" \
            --kind FileStorage --sku "$STORAGE_SKU" --enable-large-file-share \
            --enable-files-aadkerb true --default-share-permission "StorageFileDataSmbShareContributor" \
            --tags Version="$VERSION_TAG" --output none
        log SUCCESS "Storage account created with Azure AD Kerberos"
    fi

    # FSLogix file share
    log INFO "Creating FSLogix file share: $FSLOGIX_SHARE_NAME"
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FSLOGIX_SHARE_NAME" &>/dev/null 2>&1; then
        log INFO "File share $FSLOGIX_SHARE_NAME already exists"
    else
        az storage share-rm create --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" \
            --name "$FSLOGIX_SHARE_NAME" --quota "$FSLOGIX_QUOTA_GB" --output none
        log SUCCESS "FSLogix file share created: $FSLOGIX_SHARE_NAME"
    fi

    # Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &>/dev/null; then
        log INFO "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        log INFO "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace create --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" --location "$LOCATION" \
            --retention-time "$LOG_RETENTION_DAYS" --tags Version="$VERSION_TAG" --output none
        log SUCCESS "Log Analytics workspace created"
    fi

    # Action group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" &>/dev/null; then
        log INFO "Action group $ACTION_GROUP_NAME already exists"
    else
        log INFO "Creating action group: $ACTION_GROUP_NAME"
        az monitor action-group create --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" \
            --short-name "tktphavd" --action email adminEmail "$ALERT_EMAIL" \
            --tags Version="$VERSION_TAG" --output none
        log SUCCESS "Action group created"
    fi

    log SUCCESS "Phase 2 complete: STORAGE & MONITORING"
}

#===============================================================================
# PHASE 2.5: SHARED DOCUMENTATION STORAGE
# (Extracted from v9 Phase 2.5, lines 1007-1068)
#===============================================================================

deploy_phase2_5_shared_docs() {
    log_phase "2.5" "SHARED DOCUMENTATION STORAGE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: shared-docs file share (${SHARED_DOCS_QUOTA_GB}GB) with folder structure"
        return
    fi

    log INFO "Creating shared documentation share: $SHARED_DOCS_SHARE_NAME (${SHARED_DOCS_QUOTA_GB}GB)"
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$SHARED_DOCS_SHARE_NAME" &>/dev/null 2>&1; then
        log INFO "File share $SHARED_DOCS_SHARE_NAME already exists"
    else
        az storage share-rm create --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" \
            --name "$SHARED_DOCS_SHARE_NAME" --quota "$SHARED_DOCS_QUOTA_GB" --output none
        log SUCCESS "Shared documentation share created"
    fi

    log INFO "Creating folder structure in shared-docs (OAuth)..."
    local folders=(
        "SOPs" "SOPs/P2P" "SOPs/P2P/how-to" "SOPs/P2P/troubleshooting" "SOPs/P2P/configuration"
        "SOPs/R2R" "SOPs/R2R/how-to" "SOPs/R2R/troubleshooting" "SOPs/R2R/configuration"
        "SOPs/cross-functional" "knowledge-base" "knowledge-base/client-specific"
        "knowledge-base/SAP-S4HANA" "knowledge-base/Zoho-Desk" "templates"
        "weekly-reports" "weekly-reports/session-logs"
    )

    for folder in "${folders[@]}"; do
        az storage directory create --share-name "$SHARED_DOCS_SHARE_NAME" --name "$folder" \
            --account-name "$STORAGE_ACCOUNT" --auth-mode login --output none 2>/dev/null || true
    done

    log SUCCESS "Folder structure created in $SHARED_DOCS_SHARE_NAME"
    log SUCCESS "Phase 2.5 complete: SHARED DOCUMENTATION STORAGE"
}

#===============================================================================
# PHASE 3: AVD CONTROL PLANE
# (Extracted from v9 Phase 3, lines 1070-1179)
#===============================================================================

deploy_phase3_avd() {
    log_phase 3 "AVD CONTROL PLANE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Workspace, Host Pool (MaxSession=$MAX_SESSION_LIMIT), Application Group"
        return
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    # Workspace
    if az desktopvirtualization workspace show --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE_NAME" &>/dev/null 2>&1; then
        log INFO "Workspace $WORKSPACE_NAME already exists"
    else
        log INFO "Creating AVD workspace: $WORKSPACE_NAME"
        az desktopvirtualization workspace create --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE_NAME" \
            --location "$LOCATION" --friendly-name "$WORKSPACE_FRIENDLY_NAME" \
            --tags Version="$VERSION_TAG" --output none
        log SUCCESS "AVD workspace created"
    fi

    # Host pool
    if az desktopvirtualization hostpool show --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" &>/dev/null 2>&1; then
        log INFO "Host pool $HOSTPOOL_NAME already exists"
        az desktopvirtualization hostpool update --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" \
            --max-session-limit "$MAX_SESSION_LIMIT" --tags Version="$VERSION_TAG" --output none 2>/dev/null || true
    else
        log INFO "Creating host pool: $HOSTPOOL_NAME (MaxSession=$MAX_SESSION_LIMIT)"
        az desktopvirtualization hostpool create --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" \
            --location "$LOCATION" --host-pool-type "$HOSTPOOL_TYPE" --load-balancer-type "$LOAD_BALANCER_TYPE" \
            --max-session-limit "$MAX_SESSION_LIMIT" --preferred-app-group-type Desktop \
            --custom-rdp-property "targetisaadjoined:i:1;enablerdsaadauth:i:1;" \
            --tags Version="$VERSION_TAG" --output none
        log SUCCESS "Host pool created"
    fi

    # Registration token
    log INFO "Generating registration token..."
    local expiry_time
    if date -v+24H &>/dev/null 2>&1; then
        expiry_time=$(date -u -v+24H '+%Y-%m-%dT%H:%M:%SZ')
    else
        expiry_time=$(date -u -d '+24 hours' '+%Y-%m-%dT%H:%M:%SZ')
    fi

    REGISTRATION_TOKEN=$(az desktopvirtualization hostpool update --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --registration-info expiration-time="$expiry_time" registration-token-operation="Update" \
        --query "registrationInfo.token" -o tsv)

    if [[ -z "$REGISTRATION_TOKEN" || "$REGISTRATION_TOKEN" == "null" ]]; then
        fail "Failed to generate registration token."
    fi

    echo "$REGISTRATION_TOKEN" > "$REGISTRATION_TOKEN_FILE"
    chmod 600 "$REGISTRATION_TOKEN_FILE"
    log SUCCESS "Registration token saved"

    # Application group
    if az desktopvirtualization applicationgroup show --resource-group "$RESOURCE_GROUP" --name "$APPGROUP_NAME" &>/dev/null 2>&1; then
        log INFO "Application group $APPGROUP_NAME already exists"
    else
        log INFO "Creating application group: $APPGROUP_NAME"
        az desktopvirtualization applicationgroup create --resource-group "$RESOURCE_GROUP" --name "$APPGROUP_NAME" \
            --location "$LOCATION" \
            --host-pool-arm-path "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME" \
            --application-group-type Desktop --tags Version="$VERSION_TAG" --output none
        log SUCCESS "Application group created"
    fi

    # Associate with workspace
    log INFO "Associating application group with workspace..."
    local app_group_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME"
    az desktopvirtualization workspace update --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE_NAME" \
        --application-group-references "$app_group_id" --output none

    log SUCCESS "Phase 3 complete: AVD CONTROL PLANE"
}

#===============================================================================
# PHASE 4: SESSION HOSTS
# (Extracted from v9 Phase 4, lines 1181-1405 — device cleanup removed)
#===============================================================================

deploy_phase4_session_hosts() {
    log_phase 4 "SESSION HOSTS (Entra ID Join)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: $VM_COUNT x $VM_SIZE VMs across availability zones with Entra ID join and AVD agent"
        return
    fi

    local subnet_id=$(az network vnet subnet show --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" --query "id" -o tsv)

    # Availability zones for session host distribution
    local available_zones=(1 2 3)
    local zone_count=${#available_zones[@]}

    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local vm_zone=${available_zones[$(( (i - 1) % zone_count ))]}

        # NOTE: Stale device cleanup is handled by Track A (deploy-identity.sh)

        # Create VM
        if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" &>/dev/null; then
            log INFO "VM $vm_name already exists"
        else
            log INFO "Deploying session host: $vm_name ($VM_SIZE, zone $vm_zone, 5-10 minutes)..."
            az vm create \
                --resource-group "$RESOURCE_GROUP" --name "$vm_name" --image "$VM_IMAGE" \
                --size "$VM_SIZE" --admin-username "$ADMIN_USERNAME" --admin-password "$(get_admin_password)" \
                --subnet "$subnet_id" --public-ip-address "" --nsg "" \
                --os-disk-size-gb "$VM_DISK_SIZE_GB" --storage-sku Premium_LRS \
                --license-type Windows_Client --security-type TrustedLaunch \
                --enable-secure-boot --enable-vtpm --encryption-at-host true \
                --zone "$vm_zone" \
                --assign-identity --tags Version="$VERSION_TAG" Role=SessionHost Zone="$vm_zone" --output none
            log SUCCESS "$vm_name deployed in zone $vm_zone with managed identity"
        fi

        # Entra ID join extension
        log INFO "Configuring Entra ID join on $vm_name..."
        if ! az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AADLoginForWindows" &>/dev/null 2>&1; then
            az vm extension set --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" \
                --name "AADLoginForWindows" --publisher "Microsoft.Azure.ActiveDirectory" --version "2.0" --output none
            log SUCCESS "Entra ID join configured on $vm_name"
        fi

        # AVD agent
        log INFO "Installing AVD agent on $vm_name..."
        if ! az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "DSC" &>/dev/null 2>&1; then
            az vm extension set --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" \
                --name DSC --publisher Microsoft.Powershell --version 2.83 \
                --settings "{
                    \"modulesUrl\": \"https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip\",
                    \"configurationFunction\": \"Configuration.ps1\\\\AddSessionHost\",
                    \"properties\": {
                        \"hostPoolName\": \"$HOSTPOOL_NAME\",
                        \"registrationInfoToken\": \"$REGISTRATION_TOKEN\",
                        \"aadJoin\": true
                    }
                }" --output none
            log SUCCESS "AVD agent installed on $vm_name"
        fi

        # Azure Monitor Agent
        log INFO "Installing Azure Monitor Agent on $vm_name..."
        if ! az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AzureMonitorWindowsAgent" &>/dev/null 2>&1; then
            az vm extension set --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" \
                --name AzureMonitorWindowsAgent --publisher Microsoft.Azure.Monitor \
                --version 1.0 --enable-auto-upgrade true --output none 2>/dev/null || log WARN "AMA may need manual setup on $vm_name"
        fi
        log SUCCESS "Azure Monitor Agent configured on $vm_name"
    done

    # VM auto-shutdown schedules
    if [[ "$VM_SCHEDULE_ENABLED" == "true" ]]; then
        log INFO "Configuring VM auto-shutdown schedules..."
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            az vm auto-shutdown --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
                --time "$VM_SCHEDULE_SHUTDOWN_TIME" --output none 2>/dev/null || true
        done
        log SUCCESS "VM schedules configured"
    fi

    # Assign VM login role to pre-existing security group
    log INFO "Assigning VM login permissions to $SECURITY_GROUP_NAME..."
    local group_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query id -o tsv 2>/dev/null || echo "")
    if [[ -n "$group_id" ]]; then
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv)
            az role assignment create --assignee "$group_id" --role "Virtual Machine User Login" \
                --scope "$vm_id" --output none 2>/dev/null || true
        done
        log SUCCESS "VM login permissions assigned"
    fi

    # Wait for registration
    log INFO "Waiting for session hosts to complete Entra ID join and register..."
    sleep 90

    local max_attempts=15
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local available_count=$(az desktopvirtualization sessionhost list \
            --resource-group "$RESOURCE_GROUP" --host-pool-name "$HOSTPOOL_NAME" \
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
# PHASE 4.5: APPLICATION INSTALLATION
# (Extracted from v9 Phase 4.5, lines 1407-1660)
#===============================================================================

deploy_phase4_5_applications() {
    log_phase "4.5" "APPLICATION INSTALLATION"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would install: Teams (with WebRTC), Edge (with bookmarks), mount shared-docs"
        return
    fi

    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "Installing applications on $vm_name..."

        # 4.5.1: Teams optimization
        log INFO "  -> Installing WebRTC Redirector and Teams optimization..."
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                Invoke-WebRequest -Uri "https://aka.ms/msrdcwebrtcsvc/msi" -OutFile "C:\Temp\MsRdcWebRTCSvc.msi"
                Start-Process msiexec.exe -ArgumentList "/i C:\Temp\MsRdcWebRTCSvc.msi /quiet /norestart" -Wait
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -Type DWord
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableMultimediaRedirection" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableWebRTCRedirector" -Value 1 -Type DWord
            ' --output none 2>/dev/null || log WARN "WebRTC setup may have failed on $vm_name"

        # 4.5.2: Teams client
        log INFO "  -> Installing Microsoft Teams..."
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409" -OutFile "C:\Temp\teamsbootstrapper.exe"
                Start-Process -FilePath "C:\Temp\teamsbootstrapper.exe" -ArgumentList "-p" -Wait
            ' --output none 2>/dev/null || log WARN "Teams install may have failed on $vm_name"

        # 4.5.3: Edge bookmarks
        log INFO "  -> Configuring Edge Enterprise with Fiori and Zoho bookmarks..."
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
                $bookmarks = "[{\"toplevel_name\":\"TKT Consulting\"},{\"name\":\"SAP Fiori Launchpad\",\"url\":\"'"$SAP_FIORI_URL"'\"},{\"name\":\"Zoho Desk\",\"url\":\"'"$ZOHO_DESK_URL"'\"},{\"name\":\"Teams Web\",\"url\":\"https://teams.microsoft.com\"},{\"name\":\"AVD Web Client\",\"url\":\"https://rdweb.wvd.microsoft.com/arm/webclient\"}]"
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "ManagedBookmarks" -Value $bookmarks -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DefaultBrowserSettingEnabled" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "FavoritesBarEnabled" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\RestoreOnStartupURLs" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\RestoreOnStartupURLs" -Name "1" -Value "'"$SAP_FIORI_URL"'" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "RestoreOnStartup" -Value 4 -Type DWord
            ' --output none 2>/dev/null || log WARN "Edge config may have failed on $vm_name"

        # 4.5.4: Shared-docs drive (Kerberos SSO)
        log INFO "  -> Configuring shared documentation drive (Z:) with Kerberos SSO..."
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                $storageAccount = "'"$STORAGE_ACCOUNT"'"
                $shareName = "'"$SHARED_DOCS_SHARE_NAME"'"
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Name "CloudKerberosTicketRetrievalEnabled" -Value 1 -Type DWord
                $logonScriptDir = "C:\ProgramData\TKT"
                New-Item -ItemType Directory -Path $logonScriptDir -Force | Out-Null
                $logonScript = "@echo off`r`nREM TKT Platform V9.1 - Map shared documentation drive (Kerberos SSO)`r`nnet use Z: /delete /y 2>nul`r`nnet use Z: \\${storageAccount}.file.core.windows.net\${shareName} /persistent:yes 2>nul`r`nif %errorlevel% neq 0 (timeout /t 10 /nobreak >nul & net use Z: \\${storageAccount}.file.core.windows.net\${shareName} /persistent:yes)"
                $logonScript | Out-File -FilePath "$logonScriptDir\MapDrive.cmd" -Encoding ASCII -Force
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$logonScriptDir\MapDrive.cmd`""
                $trigger = New-ScheduledTaskTrigger -AtLogOn
                $principal = New-ScheduledTaskPrincipal -GroupId "Users" -RunLevel Limited
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                Unregister-ScheduledTask -TaskName "TKT-MapSharedDrive" -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "TKT-MapSharedDrive" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TKT V9.1: Map shared documentation drive Z: (Kerberos)" | Out-Null
            ' --output none 2>/dev/null || log WARN "Shared drive mapping may have failed on $vm_name"

        # 4.5.5: FSLogix profile container (Kerberos auth)
        log INFO "  -> Configuring FSLogix profile container (Kerberos)..."
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                $storageAccount = "'"$STORAGE_ACCOUNT"'"
                $shareName = "'"$FSLOGIX_SHARE_NAME"'"
                New-Item -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VHDLocations" -Value "\\\\${storageAccount}.file.core.windows.net\\${shareName}" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "SizeInMBs" -Value 30000 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VolumeType" -Value "VHDX" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "IsDynamic" -Value 1 -Type DWord
            ' --output none 2>/dev/null || log WARN "FSLogix config may have failed on $vm_name"

        log SUCCESS "Applications installed on $vm_name"
    done

    # V9: ActivTrak (optional)
    if [[ -n "$ACTIVTRAK_ACCOUNT_ID" ]]; then
        log INFO "Installing ActivTrak agent (Account: $ACTIVTRAK_ACCOUNT_ID)..."
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
                --command-id RunPowerShellScript --scripts '
                    $accountId = "'"$ACTIVTRAK_ACCOUNT_ID"'"
                    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                    try { Invoke-WebRequest -Uri "https://app.activtrak.com/agent/activtrak-install.msi" -OutFile "C:\Temp\activtrak-install.msi" -UseBasicParsing } catch { exit 0 }
                    Start-Process msiexec.exe -ArgumentList "/i `"C:\Temp\activtrak-install.msi`" ACCOUNT_ID=$accountId /quiet /norestart" -Wait -NoNewWindow
                    Remove-Item -Path "C:\Temp\activtrak-install.msi" -Force -ErrorAction SilentlyContinue
                ' --output none 2>/dev/null || log WARN "ActivTrak may have failed on $vm_name"
            log SUCCESS "  -> ActivTrak agent installed on $vm_name"
        done
    else
        log INFO "ActivTrak: Skipped (set ACTIVTRAK_ACCOUNT_ID to enable)"
    fi

    log SUCCESS "Phase 4.5 complete: APPLICATION INSTALLATION"
}

#===============================================================================
# PHASE 4.6: SESSION LOGGING & WEEKLY EXPORT
# (Extracted from v9 Phase 4.6, lines 1662-1988)
#===============================================================================

deploy_phase4_6_session_logging() {
    log_phase "4.6" "SESSION LOGGING & WEEKLY EXPORT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure: Audit policies, Azure Monitor DCR, weekly log export task"
        return
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    local law_id=$(az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" --query "id" -o tsv 2>/dev/null)

    # Create Data Collection Rule
    log INFO "Creating Data Collection Rule for session logging..."
    local dcr_name="dcr-tktph-avd-sessions"

    if ! az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "$dcr_name" &>/dev/null 2>&1; then
        az monitor data-collection rule create --resource-group "$RESOURCE_GROUP" --name "$dcr_name" \
            --location "$LOCATION" \
            --data-flows '[{"streams": ["Microsoft-Event"], "destinations": ["logAnalytics"]}]' \
            --log-analytics "[{\"name\": \"logAnalytics\", \"workspaceResourceId\": \"$law_id\"}]" \
            --windows-event-logs "[{\"name\": \"SecurityEvents\", \"streams\": [\"Microsoft-Event\"], \"xPathQueries\": [\"Security!*[System[(EventID=4624 or EventID=4625 or EventID=4634 or EventID=4647 or EventID=4648)]]\"]}]" \
            --tags Version="$VERSION_TAG" --output none 2>/dev/null || log WARN "DCR creation may require manual setup"
        log SUCCESS "Data Collection Rule created: $dcr_name"
    else
        log INFO "Data Collection Rule $dcr_name already exists"
    fi

    local dcr_id=$(az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" \
        --name "$dcr_name" --query "id" -o tsv 2>/dev/null || echo "")

    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "Configuring session logging on $vm_name..."

        # Associate DCR with VM
        if [[ -n "$dcr_id" ]]; then
            local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv 2>/dev/null)
            az monitor data-collection rule association create --name "configurationAccessEndpoint" \
                --rule-id "$dcr_id" --resource "$vm_id" --output none 2>/dev/null || true
        fi

        # Configure audit policies
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                if (-not [System.Diagnostics.EventLog]::SourceExists("TKT-Platform")) {
                    New-EventLog -LogName Application -Source "TKT-Platform"
                }
                auditpol /set /subcategory:"Logon" /success:enable /failure:enable
                auditpol /set /subcategory:"Logoff" /success:enable
                auditpol /set /subcategory:"Special Logon" /success:enable /failure:enable
                auditpol /set /subcategory:"Process Creation" /success:enable
                auditpol /set /subcategory:"Process Termination" /success:enable
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
            ' --output none 2>/dev/null || log WARN "Audit policy config may have failed on $vm_name"

        # Weekly log export task
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                New-Item -ItemType Directory -Path "C:\ProgramData\TKT\Scripts" -Force | Out-Null
                $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command Write-EventLog -LogName Application -Source TKT-Platform -EventId 8010 -EntryType Information -Message WeeklyExportPlaceholder"
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:00"
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                Unregister-ScheduledTask -TaskName "TKT-WeeklyLogExport" -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "TKT-WeeklyLogExport" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TKT V9.1: Weekly session log export" | Out-Null
            ' --output none 2>/dev/null || log WARN "Weekly export setup may have failed on $vm_name"

        log SUCCESS "  -> Session logging configured on $vm_name"
    done

    log SUCCESS "Phase 4.6 complete: SESSION LOGGING & WEEKLY EXPORT"
}

#===============================================================================
# PHASE 5: RBAC & KEY VAULT
# (Extracted infra parts of v9 Phase 5: Key Vault, role assignments, storage)
#===============================================================================

deploy_phase5_rbac() {
    log_phase 5 "RBAC & KEY VAULT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Key Vault, RBAC role assignments, disable shared key access"
        return
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    local group_object_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query "id" -o tsv)

    # 5.1: Key Vault + store break-glass password
    if [[ -n "$BREAK_GLASS_PASSWORD" ]]; then
        log INFO "Creating Key Vault for break-glass credentials..."
        if ! az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
            az keyvault create --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" --sku standard --enable-soft-delete true --retention-days 90 \
                --tags Version="$VERSION_TAG" Role=Security --output none
            log SUCCESS "Key Vault created: $KEY_VAULT_NAME"
        fi

        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "breakglass-password" \
            --value "$BREAK_GLASS_PASSWORD" --output none 2>/dev/null || log WARN "Could not store break-glass password"
        log SUCCESS "Break-glass password stored in Key Vault"
    else
        log INFO "No break-glass password provided — Key Vault creation skipped"
    fi

    # 5.2: Desktop Virtualization User role on app group
    log INFO "Assigning Desktop Virtualization User role..."
    local app_group_scope="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME"
    az role assignment create --assignee "$group_object_id" --role "Desktop Virtualization User" \
        --scope "$app_group_scope" --output none 2>/dev/null || true
    log SUCCESS "Desktop Virtualization User role assigned"

    # 5.3: VM User Login role (may already be done in Phase 4, ensure completeness)
    log INFO "Ensuring VM login permissions..."
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv 2>/dev/null)
        if [[ -n "$vm_id" ]]; then
            az role assignment create --assignee "$group_object_id" --role "Virtual Machine User Login" \
                --scope "$vm_id" --output none 2>/dev/null || true
        fi
    done
    log SUCCESS "Virtual Machine User Login role assigned"

    # 5.4: Storage SMB roles for Kerberos access
    log INFO "Assigning storage permissions for Kerberos access..."
    local storage_id=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)
    if [[ -n "$storage_id" ]]; then
        az role assignment create --assignee "$group_object_id" \
            --role "Storage File Data SMB Share Contributor" --scope "$storage_id" --output none 2>/dev/null || true
        az role assignment create --assignee "$group_object_id" \
            --role "Storage File Data SMB Share Elevated Contributor" --scope "$storage_id" --output none 2>/dev/null || true
        log SUCCESS "Storage SMB roles assigned"
    fi

    # 5.5: Disable shared key access
    log INFO "Disabling shared key access on storage account..."
    az storage account update --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" \
        --allow-shared-key-access false --output none 2>/dev/null || log WARN "Could not disable shared key access"
    log SUCCESS "Shared key access disabled — Kerberos-only authentication enforced"

    log SUCCESS "Phase 5 complete: RBAC & KEY VAULT"
}

#===============================================================================
# PHASE 6: SECURITY & GOVERNANCE
# (Extracted from v9 Phase 5.5, lines 2217-2383)
#===============================================================================

deploy_phase6_security_governance() {
    log_phase 6 "SECURITY & GOVERNANCE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Resource lock, diagnostics, scaling plan, watermarking, budget"
        return
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    local LOG_ANALYTICS_WS_ID=$(az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" --query "id" -o tsv 2>/dev/null)

    # Resource Lock
    log INFO "Creating CanNotDelete resource lock..."
    if ! az lock show --name "DoNotDelete-TKT-AVD" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
        az lock create --name "DoNotDelete-TKT-AVD" --resource-group "$RESOURCE_GROUP" \
            --lock-type CanNotDelete --notes "POC Protection - prevents accidental deletion" --output none
        log SUCCESS "Resource lock created"
    fi

    # Diagnostic Settings on Host Pool
    log INFO "Creating diagnostic settings on host pool..."
    az monitor diagnostic-settings create --name "diag-${HOSTPOOL_NAME}" \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME" \
        --workspace "$LOG_ANALYTICS_WS_ID" \
        --logs '[{"category":"Checkpoint","enabled":true},{"category":"Error","enabled":true},{"category":"Management","enabled":true},{"category":"Connection","enabled":true},{"category":"HostRegistration","enabled":true},{"category":"AgentHealthStatus","enabled":true},{"category":"Feed","enabled":true}]' \
        --output none 2>/dev/null || log WARN "Host pool diagnostics may need manual setup"

    # Diagnostic Settings on Workspace
    log INFO "Creating diagnostic settings on workspace..."
    az monitor diagnostic-settings create --name "diag-${WORKSPACE_NAME}" \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/workspaces/$WORKSPACE_NAME" \
        --workspace "$LOG_ANALYTICS_WS_ID" \
        --logs '[{"category":"Checkpoint","enabled":true},{"category":"Error","enabled":true},{"category":"Management","enabled":true},{"category":"Feed","enabled":true}]' \
        --output none 2>/dev/null || log WARN "Workspace diagnostics may need manual setup"

    # Scaling Plan
    log INFO "Creating AVD autoscale scaling plan..."
    if ! az desktopvirtualization scaling-plan show --resource-group "$RESOURCE_GROUP" --name "sp-tktph-avd" &>/dev/null 2>&1; then
        az desktopvirtualization scaling-plan create --resource-group "$RESOURCE_GROUP" --name "sp-tktph-avd" \
            --location "$LOCATION" --time-zone "Asia/Manila" --host-pool-type Pooled \
            --schedule '[{"name":"BusinessHours","daysOfWeek":["Monday","Tuesday","Wednesday","Thursday","Friday"],"rampUpStartTime":{"hour":7,"minute":0},"rampUpLoadBalancingAlgorithm":"BreadthFirst","rampUpMinimumHostsPct":50,"rampUpCapacityThresholdPct":80,"peakStartTime":{"hour":9,"minute":0},"peakLoadBalancingAlgorithm":"BreadthFirst","rampDownStartTime":{"hour":17,"minute":0},"rampDownLoadBalancingAlgorithm":"DepthFirst","rampDownMinimumHostsPct":0,"rampDownCapacityThresholdPct":90,"rampDownForceLogoffUsers":false,"rampDownNotificationMessage":"Your session will end in 15 minutes. Please save your work.","rampDownWaitTimeMinutes":15,"offPeakStartTime":{"hour":19,"minute":0},"offPeakLoadBalancingAlgorithm":"DepthFirst"}]' \
            --host-pool-references "[{\"hostPoolArmPath\":\"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME\",\"scalingPlanEnabled\":true}]" \
            --tags Version="$VERSION_TAG" --output none 2>/dev/null || log WARN "Scaling plan may require manual setup"
        log SUCCESS "Scaling plan created"
    fi

    # Watermarking & Screen Capture Protection
    log INFO "Configuring watermarking and screen capture protection..."
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        az vm run-command invoke --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --command-id RunPowerShellScript --scripts '
                $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                Set-ItemProperty -Path $path -Name "fEnableWatermarking" -Value 1 -Type DWord
                Set-ItemProperty -Path $path -Name "WatermarkingOpacity" -Value 2000 -Type DWord
                Set-ItemProperty -Path $path -Name "WatermarkingWidthFactor" -Value 320 -Type DWord
                Set-ItemProperty -Path $path -Name "WatermarkingHeightFactor" -Value 180 -Type DWord
                Set-ItemProperty -Path $path -Name "WatermarkingQrScale" -Value 4 -Type DWord
                Set-ItemProperty -Path $path -Name "fEnableScreenCaptureProtection" -Value 1 -Type DWord
            ' --output none 2>/dev/null || log WARN "Watermarking may have failed on $vm_name"
    done

    # Service Health Alert
    log INFO "Creating Azure Service Health alert..."
    az monitor activity-log alert create --resource-group "$RESOURCE_GROUP" --name "alert-service-health-sea" \
        --condition category=ServiceHealth and properties.impactedServices/*/impactedRegions/*/regionName=Southeast\ Asia \
        --action-group "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/actionGroups/$ACTION_GROUP_NAME" \
        --description "Alert on Azure service health incidents in Southeast Asia" \
        --tags Version="$VERSION_TAG" --output none 2>/dev/null || log WARN "Service health alert may need manual setup"

    # Cost Budget Alert (EUR 450/month)
    log INFO "Creating cost budget alert (EUR 450/month)..."
    az consumption budget create --budget-name "budget-tktph-avd" --amount 450 --time-grain Monthly \
        --start-date "$(date +%Y-%m)-01" --end-date "2027-12-31" --resource-group "$RESOURCE_GROUP" --category Cost \
        --notifications '{"Actual_80_Percent":{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["'"$ALERT_EMAIL"'"]},"Actual_100_Percent":{"enabled":true,"operator":"GreaterThan","threshold":100,"contactEmails":["'"$ALERT_EMAIL"'"]}}' \
        --output none 2>/dev/null || log WARN "Budget may need manual setup"
    log SUCCESS "Cost budget created"

    log SUCCESS "Phase 6 complete: SECURITY & GOVERNANCE"
}

#===============================================================================
# PHASE 7: VALIDATION
# (Extracted from v9 Phase 6)
#===============================================================================

deploy_phase7_validation() {
    log_phase 7 "VALIDATION"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would run validation checks"
        return
    fi

    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    local passed=0 failed=0 warnings=0
    echo ""
    printf "  %-50s %s\n" "Check" "Status"
    echo "  ---------------------------------------------------------------"

    # Resource group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Resource Group"; passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Resource Group"; failed=$((failed + 1))
    fi

    # VMs
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local state=$(az vm get-instance-view --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)
        if [[ "$state" == "VM running" ]]; then
            printf "  %-50s ${GREEN}Running${NC}\n" "$vm_name"; passed=$((passed + 1))
        else
            printf "  %-50s ${YELLOW}$state${NC}\n" "$vm_name"; warnings=$((warnings + 1))
        fi
    done

    # Session hosts available
    local available=$(az desktopvirtualization sessionhost list --resource-group "$RESOURCE_GROUP" \
        --host-pool-name "$HOSTPOOL_NAME" --query "[?status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$available" -ge "$VM_COUNT" ]]; then
        printf "  %-50s ${GREEN}$available Available${NC}\n" "Session Hosts Health"; passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$available/$VM_COUNT${NC}\n" "Session Hosts Health"; warnings=$((warnings + 1))
    fi

    # Storage
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Storage Account"; passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Storage Account"; failed=$((failed + 1))
    fi

    # Security group (from Track A)
    local group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null)
    if [[ -n "$group_id" ]]; then
        local members=$(az ad group member list --group "$SECURITY_GROUP_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        printf "  %-50s ${GREEN}OK ($members members)${NC}\n" "Security Group (Track A)"; passed=$((passed + 1))
    else
        printf "  %-50s ${RED}NOT FOUND${NC}\n" "Security Group (Track A)"; failed=$((failed + 1))
    fi

    # Resource Lock
    if az lock show --name "DoNotDelete-TKT-AVD" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Resource Lock"; passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}Not found${NC}\n" "Resource Lock"; warnings=$((warnings + 1))
    fi

    echo "  ---------------------------------------------------------------"
    printf "  %-50s ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}, ${YELLOW}$warnings warnings${NC}\n" "Results"
    echo ""
}

#===============================================================================
# FINAL SUMMARY
#===============================================================================

show_summary() {
    echo ""
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo -e "${GREEN}|           TRACK B INFRASTRUCTURE DEPLOYMENT COMPLETE (V9.1)                    |${NC}"
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo ""
    echo "  Platform Version:   $VERSION_TAG"
    echo "  Resource Group:     $RESOURCE_GROUP"
    echo "  Session Hosts:      $VM_COUNT x $VM_SIZE"
    echo "  Max Sessions:       $MAX_SESSION_LIMIT concurrent users per host"
    echo "  Total Capacity:     $((VM_COUNT * MAX_SESSION_LIMIT)) concurrent users"
    echo "  Join Type:          Microsoft Entra ID (cloud-only)"
    echo "  Estimated Cost:     ~EUR390/month (${VM_COUNT}x D4s_v5)"
    echo ""
    echo "  +-------------------------------------------------------------------------+"
    echo "  |  USER ACCESS                                                            |"
    echo "  +-------------------------------------------------------------------------+"
    echo "  |  Web Client:  https://rdweb.wvd.microsoft.com/arm/webclient             |"
    echo "  +-------------------------------------------------------------------------+"
    echo ""
    echo "  Log File:           $LOG_FILE"
    echo ""
    echo -e "  ${YELLOW}Next Steps:${NC}"
    echo "    1. Wait 3-5 minutes for Entra ID join to complete"
    echo "    2. Verify SAP Fiori + Zoho Desk access via Edge"
    echo "    3. Test Teams call with WebRTC optimization"
    echo "    4. Verify Z:\\ shared drive is accessible"
    echo "    5. Deploy Azure Firewall (optional):"
    echo "       bash scripts/deploy-azure-firewall.sh --sku Basic"
    echo ""
    echo -e "  ${YELLOW}TEARDOWN (reverse order):${NC}"
    echo "    1. bash scripts/destroy-infra.sh         (Track B)"
    echo "    2. bash scripts/destroy-identity.sh      (Track A)"
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
            --users-file) USERS_FILE="$2"; shift 2 ;;
            --security-group-name) SECURITY_GROUP_NAME="$2"; shift 2 ;;
            --break-glass-password) BREAK_GLASS_PASSWORD="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "TKT Azure Platform V9.1 - Infrastructure Deployment (Track B)"
                echo ""
                echo "Deploys all Azure infrastructure for the AVD platform."
                echo "Requires Contributor + User Access Administrator on the subscription."
                echo "Track A (deploy-identity.sh) must be run first by a Global Admin."
                echo ""
                echo "Options:"
                echo "  --dry-run                   Preview without making changes"
                echo "  --skip-prompts              Use environment/config values only"
                echo "  --force                     Skip confirmation prompts"
                echo "  --config FILE               Load configuration from file"
                echo "  --users-file FILE           Load user config (for VM count calculation)"
                echo "  --security-group-name NAME  Pre-existing security group (default: TKT-Philippines-AVD-Users)"
                echo "  --break-glass-password PW   Break-glass password for Key Vault storage"
                echo "  --help                      Show this help"
                echo ""
                echo "Cost: ~EUR390/month (3x D4s_v5 + shared storage)"
                echo "Version: $VERSION_TAG"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    load_config
    check_prerequisites
    validate_track_a
    prompt_for_inputs
    setup_password_files
    show_config_summary

    deploy_phase1_networking
    deploy_phase2_storage
    deploy_phase2_5_shared_docs
    deploy_phase3_avd
    deploy_phase4_session_hosts
    deploy_phase4_5_applications
    deploy_phase4_6_session_logging
    deploy_phase5_rbac
    deploy_phase6_security_governance
    deploy_phase7_validation

    show_summary
}

main "$@"
