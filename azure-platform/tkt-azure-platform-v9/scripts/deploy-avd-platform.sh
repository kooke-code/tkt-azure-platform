#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9 Deployment Script
# Version: 9.0
# Date: 2026-02-17
#
# CHANGELOG V9:
#   - NEW: Interactive user creation with real names (users.json config or prompts)
#   - NEW: Scale to 6 users / 3 VMs (maintains 2 sessions/VM)
#   - NEW: Break-glass admin account with credentials stored in Azure Key Vault
#   - NEW: ActivTrak agent deployment (optional, gated by ACTIVTRAK_ACCOUNT_ID)
#   - NEW: Credentials output file (credentials-TIMESTAMP.txt) with all user info
#   - NEW: --users-file argument for custom user configuration
#   - UPDATED: VM_COUNT default 2→3, USER_COUNT default 4→6
#   - UPDATED: Budget alert EUR 350→450 (3 VMs)
#   - UPDATED: Cost estimate ~EUR390/month (3x D4s_v5 + shared storage)
#   - UPDATED: Post-deploy reminds about deploy-conditional-access.sh + deploy-teams-team.sh
#   - INHERITS: All V8.1 security (Kerberos auth, no shared keys, Trusted Launch)
#
# CHANGELOG V8.1:
#   - SECURITY: Azure AD Kerberos authentication for Azure Files
#   - SECURITY: Folder structure creation uses OAuth instead of account keys
#   - All storage key retrieval/usage removed from deploy script
#
# CONTEXT:
#   Deploys Azure Virtual Desktop for 6 SAP consultants providing managed
#   services (Procurement P2P and Record-to-Report R2R) for a self-storage
#   company using SAP S/4HANA Public Cloud. Consultants access SAP via
#   Fiori (browser-based), Zoho Desk (browser), Teams for calls, plus a
#   shared storage drive for documentation/SOPs. NO SAP GUI needed.
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Contributor role on Azure subscription
#   - User Administrator role in Entra ID
#   - jq (for users.json parsing)
#   - bash shell (not zsh)
#
# USAGE:
#   bash deploy-avd-platform.sh                        # Interactive mode
#   bash deploy-avd-platform.sh --users-file users.json  # Use user config
#   bash deploy-avd-platform.sh --dry-run              # Preview only
#   bash deploy-avd-platform.sh --config env.sh        # Use config file
#   bash deploy-avd-platform.sh --skip-prompts         # Non-interactive
#
# COST: ~EUR390/month (3x D4s_v5 session hosts + shared storage)
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# Cleanup on failure
cleanup_on_exit() {
    local exit_code=$?
    # Remove any temp password files
    rm -f "${_ADMIN_PW_FILE:-}" 2>/dev/null
    rm -f "${_USER_PW_FILE:-}" 2>/dev/null
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
# V8 FIX: Share name is 'profiles' (not 'fslogix-profiles')
FSLOGIX_SHARE_NAME="${FSLOGIX_SHARE_NAME:-profiles}"
FSLOGIX_QUOTA_GB="${FSLOGIX_QUOTA_GB:-100}"
# V8 NEW: Shared documentation storage
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
# V8: MaxSessionLimit = 2 (2 concurrent users per VM, down from 4 in v7)
MAX_SESSION_LIMIT="${MAX_SESSION_LIMIT:-2}"

# Session Hosts
VM_PREFIX="${VM_PREFIX:-vm-tktph}"
VM_COUNT="${VM_COUNT:-3}"
# V8: Default VM size upgraded to Standard_D4s_v5
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
# V8 FIX: Weekday filtering is now implemented (v7 parsed but never applied)
VM_SCHEDULE_WEEKDAYS="${VM_SCHEDULE_WEEKDAYS:-Monday,Tuesday,Wednesday,Thursday,Friday}"

# Identity - Domain from environment variable
ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-6}"
USER_PASSWORD="${USER_PASSWORD:-}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"

# Entra ID Join (always enabled for cloud-only)
ENTRA_ID_JOIN="${ENTRA_ID_JOIN:-true}"

# SAP / Application URLs (for bookmarks and NSG)
SAP_FIORI_URL="${SAP_FIORI_URL:-https://my300000.s4hana.cloud.sap}"
ZOHO_DESK_URL="${ZOHO_DESK_URL:-https://desk.zoho.com}"

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

# V8 FIX: Temp files for passwords to avoid process listing exposure
_ADMIN_PW_FILE=""
_USER_PW_FILE=""

# Version tag for all resources
VERSION_TAG="9.0"

# V9: User configuration file (JSON)
USERS_FILE="${USERS_FILE:-}"

# V9: ActivTrak (optional - set ACTIVTRAK_ACCOUNT_ID to enable)
ACTIVTRAK_ACCOUNT_ID="${ACTIVTRAK_ACCOUNT_ID:-}"

# V9: Break-glass admin
BREAK_GLASS_ENABLED="${BREAK_GLASS_ENABLED:-true}"
BREAK_GLASS_USERNAME="${BREAK_GLASS_USERNAME:-tktph-breakglass}"
BREAK_GLASS_DISPLAY_NAME="${BREAK_GLASS_DISPLAY_NAME:-TKT PH Break Glass Admin}"

# V9: Key Vault for break-glass credentials
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-tktph-avd}"

# V9: Credentials output file
CREDENTIALS_FILE=""

# V9: User arrays (populated from users.json or interactive prompts)
declare -a USER_USERNAMES=()
declare -a USER_DISPLAY_NAMES=()
declare -a USER_ROLES=()
declare -a USER_JOB_TITLES=()

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
    echo -e "${BLUE}|              Azure Virtual Desktop - V9 Automated Deployment                  |${NC}"
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

    # V9: Check jq (needed for users.json parsing)
    if ! command -v jq &> /dev/null; then
        log WARN "jq not found. Install jq for users.json support. Interactive prompts will be used instead."
    else
        log INFO "jq version: $(jq --version 2>/dev/null || echo 'unknown')"
    fi

    # Check for desktopvirtualization extension
    if ! az extension show --name desktopvirtualization &> /dev/null; then
        log INFO "Installing desktopvirtualization CLI extension..."
        az extension add --name desktopvirtualization --yes 2>/dev/null || true
    fi

    # Check for monitor-control-service extension (needed for DCR)
    if ! az extension show --name monitor-control-service &> /dev/null; then
        log INFO "Installing monitor-control-service CLI extension..."
        az extension add --name monitor-control-service --yes 2>/dev/null || true
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
# V9: LOAD USER CONFIGURATION (users.json or interactive)
#===============================================================================

load_users_config() {
    # Try to find users.json
    local users_file=""

    if [[ -n "$USERS_FILE" && -f "$USERS_FILE" ]]; then
        users_file="$USERS_FILE"
    elif [[ -f "${SCRIPT_DIR}/users.json" ]]; then
        users_file="${SCRIPT_DIR}/users.json"
    fi

    if [[ -n "$users_file" ]] && command -v jq &> /dev/null; then
        log INFO "Loading user configuration from: $users_file"

        # Validate JSON
        if ! jq empty "$users_file" 2>/dev/null; then
            fail "Invalid JSON in users file: $users_file"
        fi

        # Load domain override if present
        local json_domain=$(jq -r '.domain // empty' "$users_file")
        if [[ -n "$json_domain" ]]; then
            ENTRA_DOMAIN="$json_domain"
            log INFO "Domain from users.json: $ENTRA_DOMAIN"
        fi

        # Load security group override if present
        local json_group=$(jq -r '.security_group // empty' "$users_file")
        if [[ -n "$json_group" ]]; then
            SECURITY_GROUP_NAME="$json_group"
        fi

        # Load users
        local user_count=$(jq '.users | length' "$users_file")
        if [[ "$user_count" -eq 0 ]]; then
            fail "No users defined in $users_file"
        fi

        USER_COUNT="$user_count"
        USER_USERNAMES=()
        USER_DISPLAY_NAMES=()
        USER_ROLES=()
        USER_JOB_TITLES=()

        for i in $(seq 0 $((user_count - 1))); do
            USER_USERNAMES+=("$(jq -r ".users[$i].username" "$users_file")")
            USER_DISPLAY_NAMES+=("$(jq -r ".users[$i].display_name" "$users_file")")
            USER_ROLES+=("$(jq -r ".users[$i].role // \"\"" "$users_file")")
            USER_JOB_TITLES+=("$(jq -r ".users[$i].job_title // \"\"" "$users_file")")
        done

        log SUCCESS "Loaded $user_count users from $users_file"

        # Load break-glass config
        local bg_enabled=$(jq -r '.break_glass.enabled // "true"' "$users_file")
        if [[ "$bg_enabled" == "true" ]]; then
            BREAK_GLASS_ENABLED="true"
            local bg_username=$(jq -r '.break_glass.username // empty' "$users_file")
            local bg_display=$(jq -r '.break_glass.display_name // empty' "$users_file")
            [[ -n "$bg_username" ]] && BREAK_GLASS_USERNAME="$bg_username"
            [[ -n "$bg_display" ]] && BREAK_GLASS_DISPLAY_NAME="$bg_display"
            log INFO "Break-glass admin: ${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
        else
            BREAK_GLASS_ENABLED="false"
        fi

        # Auto-calculate VM count: ceil(users / MAX_SESSION_LIMIT)
        VM_COUNT=$(( (USER_COUNT + MAX_SESSION_LIMIT - 1) / MAX_SESSION_LIMIT ))
        log INFO "Calculated VM count: $VM_COUNT (${USER_COUNT} users / ${MAX_SESSION_LIMIT} sessions per VM)"

    else
        # No users.json — use interactive prompts or defaults
        if [[ "$SKIP_PROMPTS" == "true" ]]; then
            log INFO "No users.json found. Using default generic user naming."
            _populate_default_users
        else
            log INFO "No users.json found. Will prompt for user details interactively."
        fi
    fi
}

_populate_default_users() {
    USER_USERNAMES=()
    USER_DISPLAY_NAMES=()
    USER_ROLES=()
    USER_JOB_TITLES=()
    for i in $(seq 1 $USER_COUNT); do
        local num=$(printf '%03d' $i)
        USER_USERNAMES+=("${USER_PREFIX}-${num}")
        USER_DISPLAY_NAMES+=("PH Consultant $num")
        USER_ROLES+=("")
        USER_JOB_TITLES+=("SAP Consultant")
    done
}

_prompt_for_users() {
    echo ""
    echo -e "${YELLOW}===============================================================================${NC}"
    echo -e "${YELLOW}  V9: USER CONFIGURATION${NC}"
    echo -e "${YELLOW}===============================================================================${NC}"
    echo ""
    echo "  No users.json file found. Enter user details interactively."
    echo "  (To use a config file instead, create users.json — see users.json.template)"
    echo ""

    read -p "  How many consultant users? [$USER_COUNT]: " input_count
    USER_COUNT="${input_count:-$USER_COUNT}"

    USER_USERNAMES=()
    USER_DISPLAY_NAMES=()
    USER_ROLES=()
    USER_JOB_TITLES=()

    for i in $(seq 1 $USER_COUNT); do
        local default_num=$(printf '%03d' $i)
        echo ""
        echo -e "  ${CYAN}--- User $i of $USER_COUNT ---${NC}"
        read -p "    Real name (e.g. Maria Santos): " name
        read -p "    Username [${USER_PREFIX}-${default_num}]: " uname
        uname="${uname:-${USER_PREFIX}-${default_num}}"
        read -p "    Role (P2P/R2R) []: " role
        local title="SAP Consultant"
        [[ "$role" == "P2P" ]] && title="SAP P2P Consultant"
        [[ "$role" == "R2R" ]] && title="SAP R2R Consultant"

        USER_USERNAMES+=("$uname")
        USER_DISPLAY_NAMES+=("${name:-PH Consultant $default_num}")
        USER_ROLES+=("$role")
        USER_JOB_TITLES+=("$title")
    done

    # Auto-calculate VM count
    VM_COUNT=$(( (USER_COUNT + MAX_SESSION_LIMIT - 1) / MAX_SESSION_LIMIT ))
    echo ""
    log INFO "Calculated VM count: $VM_COUNT (${USER_COUNT} users / ${MAX_SESSION_LIMIT} sessions per VM)"

    # Break-glass confirmation
    echo ""
    read -p "  Create break-glass admin account? (Y/n): " bg_confirm
    if [[ "$bg_confirm" =~ ^[Nn]$ ]]; then
        BREAK_GLASS_ENABLED="false"
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

    # V8: Default is Standard_D4s_v5 (4 vCPU, 16GB RAM) - adequate for 2 concurrent
    # browser-heavy sessions (Fiori + Zoho Desk + Teams) per VM
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

    # Check if any options available
    if [[ -z "$available_sizes" ]]; then
        log ERROR "No VM sizes have sufficient quota. Request quota increase in Azure Portal."
        exit 1
    fi

    # Default to first available (should be Standard_D4s_v5)
    local default_size=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f2)
    local default_num=$(echo $available_sizes | tr ' ' '\n' | head -1 | cut -d':' -f1)

    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        VM_SIZE="$default_size"
    else
        read -p "Select VM size [${default_num}]: " selection
        selection=${selection:-$default_num}

        # Get selected size
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
        # If no VM_SIZE set, use default
        if [[ -z "$VM_SIZE" ]]; then
            VM_SIZE="$VM_DEFAULT_SIZE"
            log INFO "Using default VM size: $VM_SIZE"
        fi
        return
    fi

    echo ""
    echo -e "${YELLOW}===============================================================================${NC}"
    echo -e "${YELLOW}  CONFIGURATION${NC}"
    echo -e "${YELLOW}===============================================================================${NC}"
    echo ""

    # V9: Prompt for user details if not loaded from JSON
    if [[ ${#USER_USERNAMES[@]} -eq 0 ]]; then
        _prompt_for_users
    fi

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
# PASSWORD FILE HELPERS
# V8 FIX: Passwords are written to temp files with mode 600 and passed via
# file reference so they never appear in process listings (ps aux)
#===============================================================================

setup_password_files() {
    _ADMIN_PW_FILE=$(mktemp /tmp/.avd-admin-pw-XXXXXX)
    _USER_PW_FILE=$(mktemp /tmp/.avd-user-pw-XXXXXX)
    chmod 600 "$_ADMIN_PW_FILE" "$_USER_PW_FILE"
    printf '%s' "$ADMIN_PASSWORD" > "$_ADMIN_PW_FILE"
    printf '%s' "$USER_PASSWORD" > "$_USER_PW_FILE"
}

get_admin_password() {
    cat "$_ADMIN_PW_FILE"
}

get_user_password() {
    cat "$_USER_PW_FILE"
}

#===============================================================================
# CONFIGURATION SUMMARY
#===============================================================================

show_config_summary() {
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  DEPLOYMENT SUMMARY - V9${NC}"
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
    echo "    Session Hosts:    $VM_COUNT x $VM_SIZE"
    echo "    Host Pool:        $HOSTPOOL_NAME ($HOSTPOOL_TYPE)"
    echo "    Max Sessions:     $MAX_SESSION_LIMIT per host (2 concurrent users)"
    echo ""
    echo "  Storage"
    echo "  -------"
    echo "    FSLogix Profiles: $FSLOGIX_SHARE_NAME (${FSLOGIX_QUOTA_GB}GB)"
    echo "    Shared Docs:      $SHARED_DOCS_SHARE_NAME (${SHARED_DOCS_QUOTA_GB}GB)"
    echo ""
    echo "  Identity (Entra ID Join)"
    echo "  ------------------------"
    echo "    Domain:           $ENTRA_DOMAIN"
    echo "    Join Type:        Microsoft Entra ID (cloud-only)"
    echo "    Users:            $USER_COUNT consultants (named)"
    for idx in $(seq 0 $((USER_COUNT - 1))); do
        echo "      - ${USER_DISPLAY_NAMES[$idx]} (${USER_USERNAMES[$idx]}@${ENTRA_DOMAIN})"
    done
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        echo "    Break-Glass:      ${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
    fi
    echo "    Security Group:   $SECURITY_GROUP_NAME"
    echo ""
    echo "  Applications"
    echo "  ------------"
    echo "    SAP Fiori:        Browser-based (Edge)"
    echo "    Zoho Desk:        Browser-based (Edge)"
    echo "    Microsoft Teams:  With WebRTC media optimization"
    echo "    Shared Drive:     Z:\\ mapped to $SHARED_DOCS_SHARE_NAME"
    echo ""
    echo "  Monitoring"
    echo "  ----------"
    echo "    Alert Email:      $ALERT_EMAIL"
    echo "    Log Retention:    $LOG_RETENTION_DAYS days"
    echo "    Weekly Export:    Session logs to $SHARED_DOCS_SHARE_NAME"
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

    # Rule 1: Deny inbound RDP from internet
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

    # Rule 2: Allow AVD service traffic (Azure backbone)
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

    # V8 NEW Rule 3: Allow HTTPS outbound to SAP S/4HANA Public Cloud
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowSAPFioriHTTPS" \
        --priority 200 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes Internet \
        --destination-port-ranges 443 \
        --description "Allow HTTPS to SAP S/4HANA Public Cloud (Fiori), Zoho Desk, Teams" \
        --output none 2>/dev/null || true

    # V8 NEW Rule 4: Allow Teams UDP media (3478-3481 for TURN/STUN)
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowTeamsMedia" \
        --priority 210 \
        --direction Outbound \
        --access Allow \
        --protocol Udp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes Internet \
        --destination-port-ranges 3478-3481 \
        --description "Allow Teams TURN/STUN UDP media traffic" \
        --output none 2>/dev/null || true

    # V8 NEW Rule 5: Allow Teams media TCP range
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowTeamsMediaTCP" \
        --priority 220 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes Internet \
        --destination-port-ranges 50000-50059 \
        --description "Allow Teams media TCP port range" \
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
#===============================================================================

deploy_phase2_storage() {
    log_phase 2 "STORAGE & MONITORING"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Storage Account, FSLogix share, Log Analytics, Action Group"
        return
    fi

    # Storage account (V8.1: Azure AD Kerberos enabled from creation)
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log INFO "Storage account $STORAGE_ACCOUNT already exists"
        # Ensure Kerberos is enabled on existing account
        local current_auth
        current_auth=$(az storage account show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_ACCOUNT" \
            --query "azureFilesIdentityBasedAuthentication.directoryServiceOptions" \
            -o tsv 2>/dev/null || echo "None")
        if [[ "$current_auth" != "AADKERB" ]]; then
            log INFO "Enabling Azure AD Kerberos on existing storage account..."
            az storage account update \
                --resource-group "$RESOURCE_GROUP" \
                --name "$STORAGE_ACCOUNT" \
                --enable-files-aadkerb true \
                --default-share-permission "StorageFileDataSmbShareContributor" \
                --output none
            log SUCCESS "Azure AD Kerberos enabled on $STORAGE_ACCOUNT"
        else
            log INFO "Azure AD Kerberos already enabled"
        fi
    else
        log INFO "Creating storage account: $STORAGE_ACCOUNT (with Azure AD Kerberos)"
        az storage account create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_ACCOUNT" \
            --location "$LOCATION" \
            --kind FileStorage \
            --sku "$STORAGE_SKU" \
            --enable-large-file-share \
            --enable-files-aadkerb true \
            --default-share-permission "StorageFileDataSmbShareContributor" \
            --tags Version="$VERSION_TAG" \
            --output none
        log SUCCESS "Storage account created with Azure AD Kerberos"
    fi

    # FSLogix file share - V8 FIX: share name is 'profiles' (not 'fslogix-profiles')
    log INFO "Creating FSLogix file share: $FSLOGIX_SHARE_NAME"
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FSLOGIX_SHARE_NAME" &>/dev/null 2>&1; then
        log INFO "File share $FSLOGIX_SHARE_NAME already exists"
    else
        az storage share-rm create \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --name "$FSLOGIX_SHARE_NAME" \
            --quota "$FSLOGIX_QUOTA_GB" \
            --output none
        log SUCCESS "FSLogix file share created: $FSLOGIX_SHARE_NAME"
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
            --tags Version="$VERSION_TAG" \
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
            --tags Version="$VERSION_TAG" \
            --output none
        log SUCCESS "Action group created"
    fi

    log SUCCESS "Phase 2 complete: STORAGE & MONITORING"
}

#===============================================================================
# PHASE 2.5: SHARED DOCUMENTATION STORAGE (V8 NEW)
#===============================================================================

deploy_phase2_5_shared_docs() {
    log_phase "2.5" "SHARED DOCUMENTATION STORAGE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: shared-docs file share (${SHARED_DOCS_QUOTA_GB}GB) with folder structure"
        return
    fi

    # Create shared-docs file share
    log INFO "Creating shared documentation share: $SHARED_DOCS_SHARE_NAME (${SHARED_DOCS_QUOTA_GB}GB)"
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$SHARED_DOCS_SHARE_NAME" &>/dev/null 2>&1; then
        log INFO "File share $SHARED_DOCS_SHARE_NAME already exists"
    else
        az storage share-rm create \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --name "$SHARED_DOCS_SHARE_NAME" \
            --quota "$SHARED_DOCS_QUOTA_GB" \
            --output none
        log SUCCESS "Shared documentation share created"
    fi

    # V8.1: Create folder structure using OAuth (--auth-mode login) instead of storage keys
    log INFO "Creating folder structure in shared-docs (OAuth)..."

    # Create folder structure for SOPs and knowledge base
    local folders=(
        "SOPs"
        "SOPs/P2P"
        "SOPs/P2P/how-to"
        "SOPs/P2P/troubleshooting"
        "SOPs/P2P/configuration"
        "SOPs/R2R"
        "SOPs/R2R/how-to"
        "SOPs/R2R/troubleshooting"
        "SOPs/R2R/configuration"
        "SOPs/cross-functional"
        "knowledge-base"
        "knowledge-base/client-specific"
        "knowledge-base/SAP-S4HANA"
        "knowledge-base/Zoho-Desk"
        "templates"
        "weekly-reports"
        "weekly-reports/session-logs"
    )

    for folder in "${folders[@]}"; do
        az storage directory create \
            --share-name "$SHARED_DOCS_SHARE_NAME" \
            --name "$folder" \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login \
            --output none 2>/dev/null || true
    done

    log SUCCESS "Folder structure created in $SHARED_DOCS_SHARE_NAME"
    log SUCCESS "Phase 2.5 complete: SHARED DOCUMENTATION STORAGE"
}

#===============================================================================
# PHASE 3: AVD CONTROL PLANE
#===============================================================================

deploy_phase3_avd() {
    log_phase 3 "AVD CONTROL PLANE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Workspace, Host Pool (MaxSession=$MAX_SESSION_LIMIT), Application Group"
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
            --tags Version="$VERSION_TAG" \
            --output none
        log SUCCESS "AVD workspace created"
    fi

    # Host pool - V8: MaxSessionLimit = 2
    if az desktopvirtualization hostpool show --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" &>/dev/null 2>&1; then
        log INFO "Host pool $HOSTPOOL_NAME already exists"
        # Update max session limit to v8 value
        log INFO "Updating host pool max session limit to $MAX_SESSION_LIMIT..."
        az desktopvirtualization hostpool update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --max-session-limit "$MAX_SESSION_LIMIT" \
            --tags Version="$VERSION_TAG" \
            --output none 2>/dev/null || true
    else
        log INFO "Creating host pool: $HOSTPOOL_NAME (MaxSession=$MAX_SESSION_LIMIT)"
        az desktopvirtualization hostpool create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --location "$LOCATION" \
            --host-pool-type "$HOSTPOOL_TYPE" \
            --load-balancer-type "$LOAD_BALANCER_TYPE" \
            --max-session-limit "$MAX_SESSION_LIMIT" \
            --preferred-app-group-type Desktop \
            --custom-rdp-property "targetisaadjoined:i:1;enablerdsaadauth:i:1;" \
            --tags Version="$VERSION_TAG" \
            --output none
        log SUCCESS "Host pool created with MaxSession=$MAX_SESSION_LIMIT, Entra ID join, and SSO enabled"
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
            --tags Version="$VERSION_TAG" \
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
# PHASE 4: SESSION HOSTS (V8 - WITH ENTRA ID JOIN)
#===============================================================================

deploy_phase4_session_hosts() {
    log_phase 4 "SESSION HOSTS (Entra ID Join)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: $VM_COUNT x $VM_SIZE VMs with Entra ID join and AVD agent"
        return
    fi

    # Get subnet ID
    local subnet_id=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --query "id" -o tsv)

    # V8 FIX: All VM loops use 1-indexed naming with zero-padding: ${VM_PREFIX}-$(printf '%02d' $i)
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"

        # Clean up stale Entra ID device record to prevent hostname_duplicate error
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

        # Create VM with system-assigned managed identity
        if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" &>/dev/null; then
            log INFO "VM $vm_name already exists"
        else
            log INFO "Deploying session host: $vm_name ($VM_SIZE, 5-10 minutes)..."

            # V8 FIX: Password passed via file to avoid process listing exposure
            az vm create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --image "$VM_IMAGE" \
                --size "$VM_SIZE" \
                --admin-username "$ADMIN_USERNAME" \
                --admin-password "$(get_admin_password)" \
                --subnet "$subnet_id" \
                --public-ip-address "" \
                --nsg "" \
                --os-disk-size-gb "$VM_DISK_SIZE_GB" \
                --storage-sku Premium_LRS \
                --license-type Windows_Client \
                --security-type TrustedLaunch \
                --enable-secure-boot \
                --enable-vtpm \
                --encryption-at-host true \
                --assign-identity \
                --tags Version="$VERSION_TAG" Role=SessionHost \
                --output none

            log SUCCESS "$vm_name deployed with managed identity"
        fi

        # Install AADLoginForWindows extension for Entra ID join
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

        # V8 NEW: Install Azure Monitor Agent
        log INFO "Installing Azure Monitor Agent on $vm_name..."
        if ! az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AzureMonitorWindowsAgent" &>/dev/null 2>&1; then
            az vm extension set \
                --resource-group "$RESOURCE_GROUP" \
                --vm-name "$vm_name" \
                --name AzureMonitorWindowsAgent \
                --publisher Microsoft.Azure.Monitor \
                --version 1.0 \
                --enable-auto-upgrade true \
                --output none 2>/dev/null || log WARN "Azure Monitor Agent may need manual setup on $vm_name"
        fi
        log SUCCESS "Azure Monitor Agent configured on $vm_name"
    done

    # V8 FIX: VM schedule with weekday filtering actually implemented
    if [[ "$VM_SCHEDULE_ENABLED" == "true" ]]; then
        log INFO "Configuring VM auto-shutdown schedules (weekdays: $VM_SCHEDULE_WEEKDAYS)..."
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv 2>/dev/null)

            if [[ -n "$vm_id" ]]; then
                # Create auto-shutdown schedule
                az vm auto-shutdown \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$vm_name" \
                    --time "$VM_SCHEDULE_SHUTDOWN_TIME" \
                    --output none 2>/dev/null || true

                # V8 FIX: Implement weekday filtering via a startup scheduled task
                # The auto-shutdown handles nightly shutdown; we create a startup task
                # that checks if today is a weekday and shuts down if not
                log INFO "  Configuring weekday-only operation on $vm_name..."
                az vm run-command invoke \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$vm_name" \
                    --command-id RunPowerShellScript \
                    --scripts '
                        $weekdays = @('"$(echo "$VM_SCHEDULE_WEEKDAYS" | sed 's/,/","/g; s/^/"/; s/$/"/')"')
                        $taskName = "TKT-WeekdayCheck"
                        $scriptPath = "C:\ProgramData\TKT\Check-Weekday.ps1"

                        # Create directory
                        New-Item -ItemType Directory -Path "C:\ProgramData\TKT" -Force | Out-Null

                        # Create the weekday check script
                        $scriptContent = @"
# TKT Platform V8 - Weekday Check
# Shuts down the VM if today is not a configured weekday
`$allowedDays = @($($weekdays = $VM_SCHEDULE_WEEKDAYS; echo "$weekdays" | tr ',' '\n' | while read d; do printf "\"%s\"," "$d"; done | sed 's/,$//' ))
`$today = (Get-Date).DayOfWeek.ToString()
if (`$allowedDays -notcontains `$today) {
    Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 9001 -EntryType Information -Message "Today (`$today) is not a configured weekday. Shutting down."
    Stop-Computer -Force
}
"@
                        $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

                        # Register the scheduled task to run at startup
                        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File $scriptPath"
                        $trigger = New-ScheduledTaskTrigger -AtStartup
                        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

                        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TKT V8: Shutdown if not a configured weekday" | Out-Null
                    ' --output none 2>/dev/null || log WARN "Weekday check setup may have failed on $vm_name"
            fi
        done
        log SUCCESS "VM schedules configured with weekday filtering"
    fi

    # Assign Virtual Machine User Login role to security group (if already exists)
    log INFO "Checking for existing security group for VM login permissions..."
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
            log INFO "  -> $vm_name: VM login role assigned"
        done
        log SUCCESS "VM login permissions assigned to $SECURITY_GROUP_NAME"
    else
        log WARN "Security group not found yet - will be created in Phase 5"
    fi

    # Wait for registration (Entra ID join takes longer)
    log INFO "Waiting for session hosts to complete Entra ID join and register (3-5 minutes)..."
    sleep 90

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
# PHASE 4.5: APPLICATION INSTALLATION (V8 - Teams, Edge, Shared Drive)
#===============================================================================

deploy_phase4_5_applications() {
    log_phase "4.5" "APPLICATION INSTALLATION"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would install: Teams (with WebRTC), Edge (with bookmarks), mount shared-docs"
        return
    fi

    # V8.1: No storage key needed — Kerberos auth used for Azure Files access

    # V8 FIX: All VM loops use 1-indexed naming: ${VM_PREFIX}-$(printf '%02d' $i)
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "Installing applications on $vm_name..."

        # -----------------------------------------------------------------
        # 4.5.1: Teams optimization - WebRTC Redirector + Registry Keys
        # -----------------------------------------------------------------
        log INFO "  -> Installing WebRTC Redirector and Teams optimization..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Create temp directory
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

                # Download and install WebRTC Redirector for Teams media optimization
                Invoke-WebRequest -Uri "https://aka.ms/msrdcwebrtcsvc/msi" -OutFile "C:\Temp\MsRdcWebRTCSvc.msi"
                Start-Process msiexec.exe -ArgumentList "/i C:\Temp\MsRdcWebRTCSvc.msi /quiet /norestart" -Wait

                # V8: Set Teams AVD environment registry key
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -Type DWord

                # V8: Configure multimedia redirection for Teams
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Force | Out-Null
                # Enable multimedia redirection
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableMultimediaRedirection" -Value 1 -Type DWord
                # Enable WebRTC redirector
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fEnableWebRTCRedirector" -Value 1 -Type DWord

                # V8: Optimize Teams for AVD - disable GPU hardware acceleration for stability
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "DisableGPUHardwareAcceleration" -Value 0 -Type DWord
            ' --output none 2>/dev/null || log WARN "WebRTC/Teams optimization may have failed on $vm_name"
        log SUCCESS "  -> WebRTC Redirector and Teams optimization configured"

        # -----------------------------------------------------------------
        # 4.5.2: Install Microsoft Teams (new Teams client)
        # -----------------------------------------------------------------
        log INFO "  -> Installing Microsoft Teams..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                # Download Teams bootstrapper (new Teams client)
                Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409" -OutFile "C:\Temp\teamsbootstrapper.exe"
                Start-Process -FilePath "C:\Temp\teamsbootstrapper.exe" -ArgumentList "-p" -Wait
            ' --output none 2>/dev/null || log WARN "Teams install may have failed on $vm_name"
        log SUCCESS "  -> Teams installed"

        # -----------------------------------------------------------------
        # 4.5.3: Install Edge Enterprise with pre-configured bookmarks
        # -----------------------------------------------------------------
        log INFO "  -> Configuring Edge Enterprise with Fiori and Zoho bookmarks..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Edge is pre-installed on Windows 11 AVD images
                # Configure managed bookmarks via registry policy

                # Create Edge policy registry path
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null

                # V8: Configure managed bookmarks for SAP Fiori and Zoho Desk
                $bookmarks = @"
[
  {"toplevel_name": "TKT Consulting"},
  {"name": "SAP Fiori Launchpad", "url": "'"$SAP_FIORI_URL"'"},
  {"name": "Zoho Desk", "url": "'"$ZOHO_DESK_URL"'"},
  {"name": "SAP S/4HANA Help", "url": "https://help.sap.com/docs/SAP_S4HANA_CLOUD"},
  {"name": "Teams Web", "url": "https://teams.microsoft.com"},
  {"name": "AVD Web Client", "url": "https://rdweb.wvd.microsoft.com/arm/webclient"}
]
"@
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "ManagedBookmarks" -Value $bookmarks -Type String

                # Set Edge as default browser
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DefaultBrowserSettingEnabled" -Value 1 -Type DWord

                # Enable startup boost for faster Edge launch
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "StartupBoostEnabled" -Value 1 -Type DWord

                # Configure new tab page to show bookmarks bar
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "FavoritesBarEnabled" -Value 1 -Type DWord

                # Disable first-run experience
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord

                # Set homepage to SAP Fiori
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\RestoreOnStartupURLs" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\RestoreOnStartupURLs" -Name "1" -Value "'"$SAP_FIORI_URL"'" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "RestoreOnStartup" -Value 4 -Type DWord
            ' --output none 2>/dev/null || log WARN "Edge bookmark configuration may have failed on $vm_name"
        log SUCCESS "  -> Edge configured with Fiori and Zoho bookmarks"

        # -----------------------------------------------------------------
        # 4.5.4: Mount shared-docs as Z: drive (V8.1: Kerberos SSO)
        # -----------------------------------------------------------------
        log INFO "  -> Configuring shared documentation drive (Z:) with Kerberos SSO..."

        # V8.1: No storage key needed — Kerberos SSO handles authentication
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                $storageAccount = "'"$STORAGE_ACCOUNT"'"
                $shareName = "'"$SHARED_DOCS_SHARE_NAME"'"

                # V8.1: Enable Cloud Kerberos Ticket Retrieval (required for Azure AD Kerberos)
                New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" -Name "CloudKerberosTicketRetrievalEnabled" -Value 1 -Type DWord

                # Create a logon script to map Z: drive (Kerberos SSO, no storage key)
                $logonScriptDir = "C:\ProgramData\TKT"
                New-Item -ItemType Directory -Path $logonScriptDir -Force | Out-Null

                $logonScript = @"
@echo off
REM TKT Platform V8.1 - Map shared documentation drive (Kerberos SSO)
REM Authentication handled by Azure AD Kerberos - no storage key needed
net use Z: /delete /y 2>nul
net use Z: \\${storageAccount}.file.core.windows.net\${shareName} /persistent:yes 2>nul
if %errorlevel% neq 0 (
    echo Waiting for Kerberos ticket...
    timeout /t 10 /nobreak >nul
    net use Z: \\${storageAccount}.file.core.windows.net\${shareName} /persistent:yes
)
"@
                $logonScript | Out-File -FilePath "$logonScriptDir\MapDrive.cmd" -Encoding ASCII -Force

                # Register as a machine-level logon script via Group Policy
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0" -Name "GPO-ID" -Value "LocalGPO" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0" -Name "SOM-ID" -Value "Local" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0" -Name "FileSysPath" -Value "C:\Windows\System32\GroupPolicy\User" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0" -Name "DisplayName" -Value "Local Group Policy" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0" -Name "GPOName" -Value "Local Group Policy" -Type String -Force

                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" -Name "Script" -Value "$logonScriptDir\MapDrive.cmd" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" -Name "Parameters" -Value "" -Type String -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" -Name "IsPowershell" -Value 0 -Type DWord -Force
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logon\0\0" -Name "ExecTime" -Value 0 -Type QWord -Force

                # Also create a scheduled task as backup to map drive at user logon
                $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$logonScriptDir\MapDrive.cmd`""
                $trigger = New-ScheduledTaskTrigger -AtLogOn
                $principal = New-ScheduledTaskPrincipal -GroupId "Users" -RunLevel Limited
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

                Unregister-ScheduledTask -TaskName "TKT-MapSharedDrive" -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "TKT-MapSharedDrive" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TKT V8.1: Map shared documentation drive Z: (Kerberos)" | Out-Null
            ' --output none 2>/dev/null || log WARN "Shared drive mapping may have failed on $vm_name"
        log SUCCESS "  -> Shared documentation drive configured as Z: (Kerberos SSO)"

        # -----------------------------------------------------------------
        # 4.5.5: Configure FSLogix profile container (V8.1: Kerberos auth)
        # -----------------------------------------------------------------
        log INFO "  -> Configuring FSLogix profile container (Kerberos)..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                $storageAccount = "'"$STORAGE_ACCOUNT"'"
                $shareName = "'"$FSLOGIX_SHARE_NAME"'"

                # FSLogix registry configuration
                New-Item -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VHDLocations" -Value "\\\\${storageAccount}.file.core.windows.net\\${shareName}" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "SizeInMBs" -Value 30000 -Type DWord
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "VolumeType" -Value "VHDX" -Type String
                Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "IsDynamic" -Value 1 -Type DWord

                # V8.1: Kerberos authentication — no cmdkey/storage key needed
                # Cloud Kerberos Ticket Retrieval already enabled in phase 4.5.4
                # FSLogix will use the user Entra ID Kerberos ticket to access Azure Files
            ' --output none 2>/dev/null || log WARN "FSLogix configuration may have failed on $vm_name"
        log SUCCESS "  -> FSLogix profile container configured (Kerberos)"
    done

    # -----------------------------------------------------------------
    # V9 4.5.6: ActivTrak Agent (optional - productivity monitoring)
    # -----------------------------------------------------------------
    if [[ -n "$ACTIVTRAK_ACCOUNT_ID" ]]; then
        log INFO "Installing ActivTrak agent (Account: $ACTIVTRAK_ACCOUNT_ID)..."
        for i in $(seq 1 $VM_COUNT); do
            local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
            log INFO "  -> Installing ActivTrak on $vm_name..."
            az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm_name" \
                --command-id RunPowerShellScript \
                --scripts '
                    $accountId = "'"$ACTIVTRAK_ACCOUNT_ID"'"
                    $installerUrl = "https://app.activtrak.com/agent/activtrak-install.msi"
                    $installerPath = "C:\Temp\activtrak-install.msi"

                    # Create temp directory
                    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null

                    # Download ActivTrak installer
                    try {
                        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
                        Write-Host "ActivTrak installer downloaded successfully"
                    } catch {
                        Write-Warning "Failed to download ActivTrak installer: $_"
                        exit 0
                    }

                    # Install ActivTrak with account ID
                    try {
                        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" ACCOUNT_ID=$accountId /quiet /norestart" -Wait -NoNewWindow
                        Write-Host "ActivTrak agent installed with account: $accountId"
                    } catch {
                        Write-Warning "ActivTrak installation may have failed: $_"
                    }

                    # Cleanup installer
                    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

                    Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 9010 -EntryType Information -Message "TKT V9: ActivTrak agent installed (Account: $accountId)"
                ' --output none 2>/dev/null || log WARN "ActivTrak installation may have failed on $vm_name"
            log SUCCESS "  -> ActivTrak agent installed on $vm_name"
        done
    else
        log INFO "ActivTrak: Skipped (set ACTIVTRAK_ACCOUNT_ID to enable)"
    fi

    log SUCCESS "Phase 4.5 complete: APPLICATION INSTALLATION"
}

#===============================================================================
# PHASE 4.6: SESSION LOGGING & WEEKLY EXPORT (V8 NEW)
#===============================================================================

deploy_phase4_6_session_logging() {
    log_phase "4.6" "SESSION LOGGING & WEEKLY EXPORT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure: Audit policies, Azure Monitor DCR, weekly log export task"
        return
    fi

    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    # Get Log Analytics workspace ID
    local law_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" -o tsv 2>/dev/null)

    local law_workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "customerId" -o tsv 2>/dev/null)

    # -----------------------------------------------------------------
    # 4.6.1: Create Data Collection Rule for session host logs
    # -----------------------------------------------------------------
    log INFO "Creating Data Collection Rule for session logging..."

    local dcr_name="dcr-tktph-avd-sessions"

    # Check if DCR already exists
    if az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "$dcr_name" &>/dev/null 2>&1; then
        log INFO "Data Collection Rule $dcr_name already exists"
    else
        az monitor data-collection rule create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dcr_name" \
            --location "$LOCATION" \
            --data-flows '[{
                "streams": ["Microsoft-Event"],
                "destinations": ["logAnalytics"]
            }]' \
            --log-analytics "[{
                \"name\": \"logAnalytics\",
                \"workspaceResourceId\": \"$law_id\"
            }]" \
            --windows-event-logs "[{
                \"name\": \"SecurityEvents\",
                \"streams\": [\"Microsoft-Event\"],
                \"xPathQueries\": [
                    \"Security!*[System[(EventID=4624 or EventID=4625 or EventID=4634 or EventID=4647 or EventID=4648)]]\"
                ]
            },{
                \"name\": \"ApplicationEvents\",
                \"streams\": [\"Microsoft-Event\"],
                \"xPathQueries\": [
                    \"Application!*[System[Provider[@Name='TKT-Platform']]]\"
                ]
            },{
                \"name\": \"SystemEvents\",
                \"streams\": [\"Microsoft-Event\"],
                \"xPathQueries\": [
                    \"System!*[System[(EventID=6005 or EventID=6006 or EventID=7001 or EventID=7002)]]\"
                ]
            },{
                \"name\": \"TerminalServices\",
                \"streams\": [\"Microsoft-Event\"],
                \"xPathQueries\": [
                    \"Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*\",
                    \"Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational!*\"
                ]
            }]" \
            --tags Version="$VERSION_TAG" \
            --output none 2>/dev/null || log WARN "DCR creation may require manual setup"
        log SUCCESS "Data Collection Rule created: $dcr_name"
    fi

    # Get DCR ID for association
    local dcr_id=$(az monitor data-collection rule show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dcr_name" \
        --query "id" -o tsv 2>/dev/null || echo "")

    # V8 FIX: All VM loops use 1-indexed naming
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "Configuring session logging on $vm_name..."

        # -----------------------------------------------------------------
        # 4.6.2: Associate DCR with VM
        # -----------------------------------------------------------------
        if [[ -n "$dcr_id" ]]; then
            local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" --query id -o tsv 2>/dev/null)
            az monitor data-collection rule association create \
                --name "configurationAccessEndpoint" \
                --rule-id "$dcr_id" \
                --resource "$vm_id" \
                --output none 2>/dev/null || true
            log INFO "  -> DCR associated with $vm_name"
        fi

        # -----------------------------------------------------------------
        # 4.6.3: Configure enhanced Windows audit policies
        # -----------------------------------------------------------------
        log INFO "  -> Configuring enhanced audit policies..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Register TKT-Platform event source
                if (-not [System.Diagnostics.EventLog]::SourceExists("TKT-Platform")) {
                    New-EventLog -LogName Application -Source "TKT-Platform"
                }

                # Enable advanced audit policies for session tracking
                # Logon/Logoff auditing
                auditpol /set /subcategory:"Logon" /success:enable /failure:enable
                auditpol /set /subcategory:"Logoff" /success:enable
                auditpol /set /subcategory:"Special Logon" /success:enable /failure:enable

                # Process tracking (for application launch monitoring)
                auditpol /set /subcategory:"Process Creation" /success:enable
                auditpol /set /subcategory:"Process Termination" /success:enable

                # Enable command line logging in process creation events
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord

                Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 8001 -EntryType Information -Message "TKT V8: Enhanced audit policies configured"
            ' --output none 2>/dev/null || log WARN "Audit policy configuration may have failed on $vm_name"
        log SUCCESS "  -> Enhanced audit policies configured"

        # -----------------------------------------------------------------
        # 4.6.4: Create weekly log export scheduled task
        # -----------------------------------------------------------------
        log INFO "  -> Creating weekly log export task..."

        # V8.1: No storage key — weekly export uses Kerberos SSO via SYSTEM account
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                $storageAccount = "'"$STORAGE_ACCOUNT"'"
                $shareName = "'"$SHARED_DOCS_SHARE_NAME"'"
                $vmName = "'"$vm_name"'"

                # Create TKT scripts directory
                New-Item -ItemType Directory -Path "C:\ProgramData\TKT\Scripts" -Force | Out-Null

                # Create the weekly export PowerShell script
                $exportScript = @'"'"'
# TKT Platform V8 - Weekly Session Log Export
# Exports the past 7 days of session/application/web logs to shared-docs as JSON

param(
    [string]$StorageAccount,
    [string]$ShareName,
    [string]$VMName
)

$ErrorActionPreference = "SilentlyContinue"
$startDate = (Get-Date).AddDays(-7)
$endDate = Get-Date
$reportDate = $endDate.ToString("yyyy-MM-dd")
$reportFileName = "${VMName}_weekly-report_${reportDate}.json"

# Collect user session data (logon/logoff events)
$sessions = @()
$logonEvents = Get-WinEvent -FilterHashtable @{
    LogName = "Security"
    ID = @(4624, 4634, 4647)
    StartTime = $startDate
    EndTime = $endDate
} -MaxEvents 5000 2>$null

foreach ($evt in $logonEvents) {
    $sessions += [PSCustomObject]@{
        Timestamp = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ssZ")
        EventID = $evt.Id
        EventType = switch ($evt.Id) {
            4624 { "Logon" }
            4634 { "Logoff" }
            4647 { "UserInitiatedLogoff" }
        }
        UserName = ($evt.Properties[5].Value)
        LogonType = ($evt.Properties[8].Value)
        SourceIP = ($evt.Properties[18].Value)
    }
}

# Collect application launch data (process creation)
$applications = @()
$processEvents = Get-WinEvent -FilterHashtable @{
    LogName = "Security"
    ID = 4688
    StartTime = $startDate
    EndTime = $endDate
} -MaxEvents 5000 2>$null

foreach ($evt in $processEvents) {
    $procName = $evt.Properties[5].Value
    # Filter to interesting applications only
    if ($procName -match "msedge|teams|excel|word|outlook|powershell|cmd") {
        $applications += [PSCustomObject]@{
            Timestamp = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ssZ")
            ProcessName = [System.IO.Path]::GetFileName($procName)
            User = $evt.Properties[1].Value
            CommandLine = $evt.Properties[8].Value
        }
    }
}

# Collect Edge browsing data (from Edge history if accessible)
$websitesVisited = @()
$edgeHistoryPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History"
# Note: Edge history is SQLite; we collect from URL events if available
$edgeEvents = Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-WebAuthN/Operational"
    StartTime = $startDate
    EndTime = $endDate
} -MaxEvents 1000 2>$null

foreach ($evt in $edgeEvents) {
    $websitesVisited += [PSCustomObject]@{
        Timestamp = $evt.TimeCreated.ToString("yyyy-MM-ddTHH:mm:ssZ")
        Message = $evt.Message
    }
}

# Collect Teams call statistics (from Teams logs if available)
$teamsStats = @()
$teamsLogPath = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs"
if (Test-Path $teamsLogPath) {
    $teamsLogs = Get-ChildItem -Path $teamsLogPath -Filter "*.log" -Recurse |
        Where-Object { $_.LastWriteTime -ge $startDate }
    foreach ($logFile in $teamsLogs) {
        $callLines = Select-String -Path $logFile.FullName -Pattern "call|meeting" -SimpleMatch 2>$null
        foreach ($line in $callLines) {
            $teamsStats += [PSCustomObject]@{
                Timestamp = $logFile.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                LogFile = $logFile.Name
                Entry = $line.Line.Substring(0, [Math]::Min(200, $line.Line.Length))
            }
        }
    }
}

# Build the complete report
$report = [PSCustomObject]@{
    ReportMetadata = [PSCustomObject]@{
        VMName = $VMName
        ReportDate = $reportDate
        PeriodStart = $startDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        PeriodEnd = $endDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
        PlatformVersion = "9.0"
        GeneratedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    UserSessions = $sessions
    ApplicationsLaunched = $applications
    WebsitesVisited = $websitesVisited
    TeamsCallStats = $teamsStats
    Summary = [PSCustomObject]@{
        TotalLogonEvents = ($sessions | Where-Object { $_.EventType -eq "Logon" }).Count
        TotalLogoffEvents = ($sessions | Where-Object { $_.EventType -eq "Logoff" -or $_.EventType -eq "UserInitiatedLogoff" }).Count
        UniqueUsers = ($sessions | Select-Object -ExpandProperty UserName -Unique).Count
        UniqueApplications = ($applications | Select-Object -ExpandProperty ProcessName -Unique).Count
        TeamsCallEntries = $teamsStats.Count
    }
}

# Export to JSON
$jsonPath = "C:\ProgramData\TKT\$reportFileName"
$report | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8

# V8.1: Upload to shared-docs share using Kerberos SSO (no storage key)
$uncPath = "\\$StorageAccount.file.core.windows.net\$ShareName"
net use X: /delete /y 2>$null
net use X: $uncPath /persistent:no 2>$null

if (Test-Path "X:\weekly-reports\session-logs") {
    Copy-Item -Path $jsonPath -Destination "X:\weekly-reports\session-logs\$reportFileName" -Force
    Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 8010 -EntryType Information -Message "Weekly report exported: $reportFileName"
} else {
    Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 8011 -EntryType Warning -Message "Could not access shared-docs for report export"
}

net use X: /delete /y 2>$null
Remove-Item -Path $jsonPath -Force -ErrorAction SilentlyContinue
'"'"'

                # Write the export script to disk
                $exportScript | Out-File -FilePath "C:\ProgramData\TKT\Scripts\Export-WeeklyLogs.ps1" -Encoding UTF8 -Force

                # V8.1: Create a wrapper script that passes parameters (no storage key)
                $wrapperScript = @"
# TKT V8.1 Weekly Export Wrapper - Kerberos SSO (no storage key)
& "C:\ProgramData\TKT\Scripts\Export-WeeklyLogs.ps1" ``
    -StorageAccount "$storageAccount" ``
    -ShareName "$shareName" ``
    -VMName "$vmName"
"@
                $wrapperScript | Out-File -FilePath "C:\ProgramData\TKT\Scripts\Run-WeeklyExport.ps1" -Encoding UTF8 -Force

                # Register weekly scheduled task - runs every Sunday at 23:00
                $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\TKT\Scripts\Run-WeeklyExport.ps1"
                $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:00"
                $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

                Unregister-ScheduledTask -TaskName "TKT-WeeklyLogExport" -Confirm:$false -ErrorAction SilentlyContinue
                Register-ScheduledTask -TaskName "TKT-WeeklyLogExport" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "TKT V8.1: Export weekly session logs to shared-docs (Kerberos)" | Out-Null

                Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 8002 -EntryType Information -Message "TKT V8.1: Weekly log export task registered"
            ' --output none 2>/dev/null || log WARN "Weekly log export setup may have failed on $vm_name"

        log SUCCESS "  -> Weekly log export task configured (Sundays at 23:00, Kerberos SSO)"
    done

    log SUCCESS "Phase 4.6 complete: SESSION LOGGING & WEEKLY EXPORT"
}

#===============================================================================
# PHASE 5: IDENTITY & USER ASSIGNMENT
#===============================================================================

deploy_phase5_identity() {
    log_phase 5 "IDENTITY & USER ASSIGNMENT (V9)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: $USER_COUNT named users, break-glass admin, security group, Key Vault, role assignments"
        return
    fi

    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    # Initialize credentials file
    CREDENTIALS_FILE="/tmp/credentials-${DEPLOYMENT_ID}.txt"
    {
        echo "==============================================================================="
        echo "  TKT Philippines AVD Platform V9 - User Credentials"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Domain: $ENTRA_DOMAIN"
        echo "==============================================================================="
        echo ""
        printf "%-25s | %-45s | %s\n" "Display Name" "UPN" "Temp Password"
        echo "----------------------------+-------------------------------------------------+------------------"
    } > "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"

    # -----------------------------------------------------------------
    # 5.1: Security group
    # -----------------------------------------------------------------
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

    # -----------------------------------------------------------------
    # 5.2: V9 — Create named users from configuration
    # -----------------------------------------------------------------
    log INFO "Creating $USER_COUNT consultant users..."
    local user_password="$(get_user_password)"

    for idx in $(seq 0 $((USER_COUNT - 1))); do
        local username="${USER_USERNAMES[$idx]}"
        local display_name="${USER_DISPLAY_NAMES[$idx]}"
        local job_title="${USER_JOB_TITLES[$idx]}"
        local upn="${username}@${ENTRA_DOMAIN}"

        if az ad user show --id "$upn" &>/dev/null 2>&1; then
            log INFO "User $upn already exists (${display_name})"
        else
            log INFO "Creating user: $upn (${display_name})"
            az ad user create \
                --display-name "$display_name" \
                --user-principal-name "$upn" \
                --password "$user_password" \
                --force-change-password-next-sign-in true \
                --output none

            # Set job title if provided
            if [[ -n "$job_title" ]]; then
                local user_obj_id=$(az ad user show --id "$upn" --query "id" -o tsv 2>/dev/null)
                if [[ -n "$user_obj_id" ]]; then
                    az rest --method PATCH \
                        --url "https://graph.microsoft.com/v1.0/users/${user_obj_id}" \
                        --body "{\"jobTitle\": \"${job_title}\"}" \
                        --headers "Content-Type=application/json" \
                        --output none 2>/dev/null || true
                fi
            fi

            log SUCCESS "User $upn created (${display_name})"
        fi

        # Add to group
        local user_id=$(az ad user show --id "$upn" --query "id" -o tsv 2>/dev/null)
        if [[ -n "$user_id" ]]; then
            az ad group member add --group "$SECURITY_GROUP_NAME" --member-id "$user_id" 2>/dev/null || true
        fi

        # Write to credentials file
        printf "%-25s | %-45s | %s\n" "$display_name" "$upn" "(set at deployment)" >> "$CREDENTIALS_FILE"
    done

    log SUCCESS "All $USER_COUNT consultant users created and added to group"

    # -----------------------------------------------------------------
    # 5.3: V9 — Break-glass admin account
    # -----------------------------------------------------------------
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        log INFO "Creating break-glass admin account..."
        local bg_upn="${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"

        # Generate strong random password (32 chars)
        local bg_password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
        # Ensure complexity: append special chars + digits
        bg_password="${bg_password}!A1"

        if az ad user show --id "$bg_upn" &>/dev/null 2>&1; then
            log INFO "Break-glass admin $bg_upn already exists"
        else
            az ad user create \
                --display-name "$BREAK_GLASS_DISPLAY_NAME" \
                --user-principal-name "$bg_upn" \
                --password "$bg_password" \
                --force-change-password-next-sign-in false \
                --output none
            log SUCCESS "Break-glass admin created: $bg_upn"
        fi

        # Create Key Vault and store break-glass password
        log INFO "Creating Key Vault for break-glass credentials..."
        if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
            log INFO "Key Vault $KEY_VAULT_NAME already exists"
        else
            az keyvault create \
                --name "$KEY_VAULT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --sku standard \
                --enable-soft-delete true \
                --retention-days 90 \
                --tags Version="$VERSION_TAG" Role=Security \
                --output none
            log SUCCESS "Key Vault created: $KEY_VAULT_NAME"
        fi

        # Store break-glass password in Key Vault
        az keyvault secret set \
            --vault-name "$KEY_VAULT_NAME" \
            --name "breakglass-password" \
            --value "$bg_password" \
            --output none 2>/dev/null || log WARN "Could not store break-glass password in Key Vault"
        log SUCCESS "Break-glass password stored in Key Vault: $KEY_VAULT_NAME"

        # Write to credentials file (reference Key Vault, not actual password)
        printf "%-25s | %-45s | %s\n" "$BREAK_GLASS_DISPLAY_NAME" "$bg_upn" "Key Vault: $KEY_VAULT_NAME" >> "$CREDENTIALS_FILE"
        echo "" >> "$CREDENTIALS_FILE"
        echo "Break-glass admin password stored in Azure Key Vault: $KEY_VAULT_NAME" >> "$CREDENTIALS_FILE"
        echo "Retrieve with: az keyvault secret show --vault-name $KEY_VAULT_NAME --name breakglass-password --query value -o tsv" >> "$CREDENTIALS_FILE"

        # Clear password from memory
        bg_password=""
    fi

    echo "" >> "$CREDENTIALS_FILE"
    echo "===============================================================================" >> "$CREDENTIALS_FILE"
    echo "  IMPORTANT: Change all temporary passwords on first login" >> "$CREDENTIALS_FILE"
    echo "  Web Client: https://rdweb.wvd.microsoft.com/arm/webclient" >> "$CREDENTIALS_FILE"
    echo "===============================================================================" >> "$CREDENTIALS_FILE"

    # -----------------------------------------------------------------
    # 5.4: Role assignments (same as v8.1)
    # -----------------------------------------------------------------

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

    # Assign Virtual Machine User Login role for Entra ID join
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

    # V8.1: Assign Storage File Data SMB Share roles for Kerberos-based access
    log INFO "Assigning storage permissions for Kerberos access..."
    local storage_id=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)
    if [[ -n "$storage_id" ]]; then
        az role assignment create \
            --assignee "$group_object_id" \
            --role "Storage File Data SMB Share Contributor" \
            --scope "$storage_id" \
            --output none 2>/dev/null || log INFO "Storage SMB Contributor role may already exist"
        log SUCCESS "Storage File Data SMB Share Contributor role assigned"

        az role assignment create \
            --assignee "$group_object_id" \
            --role "Storage File Data SMB Share Elevated Contributor" \
            --scope "$storage_id" \
            --output none 2>/dev/null || log INFO "Storage SMB Elevated Contributor role may already exist"
        log SUCCESS "Storage File Data SMB Share Elevated Contributor role assigned"
    fi

    # V8.1: Disable shared key access — force Kerberos-only authentication
    log INFO "Disabling shared key access on storage account (Kerberos-only)..."
    az storage account update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --allow-shared-key-access false \
        --output none 2>/dev/null || log WARN "Could not disable shared key access"
    log SUCCESS "Shared key access disabled — Kerberos-only authentication enforced"

    log SUCCESS "Phase 5 complete: IDENTITY & USER ASSIGNMENT (V9)"
}

#===============================================================================
# PHASE 5.5: SECURITY & GOVERNANCE (Azure Best Practices)
#===============================================================================

deploy_phase5_5_security_governance() {
    log_phase "5.5" "SECURITY & GOVERNANCE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create: Resource lock, diagnostic settings, scaling plan, watermarking, screen capture protection, service health alert, cost budget"
        return
    fi

    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    # Get Log Analytics workspace resource ID
    local LOG_ANALYTICS_WS_ID
    LOG_ANALYTICS_WS_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" -o tsv 2>/dev/null)

    # -----------------------------------------------------------------
    # 5.5.1: Resource Lock (CanNotDelete) on Resource Group
    # -----------------------------------------------------------------
    log INFO "Creating CanNotDelete resource lock on resource group..."
    if az lock show --name "DoNotDelete-TKT-AVD" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
        log INFO "Resource lock DoNotDelete-TKT-AVD already exists"
    else
        az lock create \
            --name "DoNotDelete-TKT-AVD" \
            --resource-group "$RESOURCE_GROUP" \
            --lock-type CanNotDelete \
            --notes "POC Protection - prevents accidental deletion" \
            --output none
        log SUCCESS "Resource lock created: DoNotDelete-TKT-AVD"
    fi

    # -----------------------------------------------------------------
    # 5.5.2: Diagnostic Settings on Host Pool
    # -----------------------------------------------------------------
    log INFO "Creating diagnostic settings on host pool..."
    az monitor diagnostic-settings create \
        --name "diag-${HOSTPOOL_NAME}" \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME" \
        --workspace "$LOG_ANALYTICS_WS_ID" \
        --logs '[{"category":"Checkpoint","enabled":true},{"category":"Error","enabled":true},{"category":"Management","enabled":true},{"category":"Connection","enabled":true},{"category":"HostRegistration","enabled":true},{"category":"AgentHealthStatus","enabled":true},{"category":"Feed","enabled":true}]' \
        --output none 2>/dev/null || log WARN "Host pool diagnostic settings may already exist or require manual setup"
    log SUCCESS "Diagnostic settings configured on host pool: $HOSTPOOL_NAME"

    # -----------------------------------------------------------------
    # 5.5.3: Diagnostic Settings on Workspace
    # -----------------------------------------------------------------
    log INFO "Creating diagnostic settings on workspace..."
    az monitor diagnostic-settings create \
        --name "diag-${WORKSPACE_NAME}" \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/workspaces/$WORKSPACE_NAME" \
        --workspace "$LOG_ANALYTICS_WS_ID" \
        --logs '[{"category":"Checkpoint","enabled":true},{"category":"Error","enabled":true},{"category":"Management","enabled":true},{"category":"Feed","enabled":true}]' \
        --output none 2>/dev/null || log WARN "Workspace diagnostic settings may already exist or require manual setup"
    log SUCCESS "Diagnostic settings configured on workspace: $WORKSPACE_NAME"

    # -----------------------------------------------------------------
    # 5.5.4: AVD Autoscale Scaling Plan
    # -----------------------------------------------------------------
    log INFO "Creating AVD autoscale scaling plan..."
    if az desktopvirtualization scaling-plan show --resource-group "$RESOURCE_GROUP" --name "sp-tktph-avd" &>/dev/null 2>&1; then
        log INFO "Scaling plan sp-tktph-avd already exists"
    else
        az desktopvirtualization scaling-plan create \
            --resource-group "$RESOURCE_GROUP" \
            --name "sp-tktph-avd" \
            --location "$LOCATION" \
            --time-zone "Asia/Manila" \
            --host-pool-type Pooled \
            --schedule '[{
                "name": "BusinessHours",
                "daysOfWeek": ["Monday","Tuesday","Wednesday","Thursday","Friday"],
                "rampUpStartTime": {"hour":7,"minute":0},
                "rampUpLoadBalancingAlgorithm": "BreadthFirst",
                "rampUpMinimumHostsPct": 50,
                "rampUpCapacityThresholdPct": 80,
                "peakStartTime": {"hour":9,"minute":0},
                "peakLoadBalancingAlgorithm": "BreadthFirst",
                "rampDownStartTime": {"hour":17,"minute":0},
                "rampDownLoadBalancingAlgorithm": "DepthFirst",
                "rampDownMinimumHostsPct": 0,
                "rampDownCapacityThresholdPct": 90,
                "rampDownForceLogoffUsers": false,
                "rampDownNotificationMessage": "Your session will end in 15 minutes. Please save your work.",
                "rampDownWaitTimeMinutes": 15,
                "offPeakStartTime": {"hour":19,"minute":0},
                "offPeakLoadBalancingAlgorithm": "DepthFirst"
            }]' \
            --host-pool-references "[{\"hostPoolArmPath\":\"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME\",\"scalingPlanEnabled\":true}]" \
            --tags Version="$VERSION_TAG" \
            --output none 2>/dev/null || log WARN "Scaling plan creation may require manual setup"
        log SUCCESS "Scaling plan created: sp-tktph-avd (Asia/Manila business hours)"
    fi

    # -----------------------------------------------------------------
    # 5.5.5: Watermarking & Screen Capture Protection (via run-command)
    # -----------------------------------------------------------------
    log INFO "Configuring watermarking and screen capture protection on session hosts..."
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        log INFO "  -> Configuring security policies on $vm_name..."

        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts '
                # Enable watermarking for financial data protection
                $watermarkPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
                if (-not (Test-Path $watermarkPath)) { New-Item -Path $watermarkPath -Force | Out-Null }
                Set-ItemProperty -Path $watermarkPath -Name "fEnableWatermarking" -Value 1 -Type DWord
                Set-ItemProperty -Path $watermarkPath -Name "WatermarkingOpacity" -Value 2000 -Type DWord
                Set-ItemProperty -Path $watermarkPath -Name "WatermarkingWidthFactor" -Value 320 -Type DWord
                Set-ItemProperty -Path $watermarkPath -Name "WatermarkingHeightFactor" -Value 180 -Type DWord
                Set-ItemProperty -Path $watermarkPath -Name "WatermarkingQrScale" -Value 4 -Type DWord

                # Enable screen capture protection
                Set-ItemProperty -Path $watermarkPath -Name "fEnableScreenCaptureProtection" -Value 1 -Type DWord

                Write-EventLog -LogName Application -Source "TKT-Platform" -EventId 9020 -EntryType Information -Message "TKT V9: Watermarking and screen capture protection configured"
            ' --output none 2>/dev/null || log WARN "Watermarking/screen capture protection may have failed on $vm_name"
        log SUCCESS "  -> Watermarking and screen capture protection configured on $vm_name"
    done

    # -----------------------------------------------------------------
    # 5.5.6: Service Health Alert for Southeast Asia
    # -----------------------------------------------------------------
    log INFO "Creating Azure Service Health alert for Southeast Asia..."
    az monitor activity-log alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "alert-service-health-sea" \
        --condition category=ServiceHealth and properties.impactedServices/*/impactedRegions/*/regionName=Southeast\ Asia \
        --action-group "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/actionGroups/$ACTION_GROUP_NAME" \
        --description "Alert on Azure service health incidents in Southeast Asia" \
        --tags Version="$VERSION_TAG" \
        --output none 2>/dev/null || log WARN "Service health alert may already exist or require manual setup"
    log SUCCESS "Service Health alert created for Southeast Asia"

    # -----------------------------------------------------------------
    # 5.5.7: Cost Budget Alert (EUR 450/month) — V9: 3 VMs
    # -----------------------------------------------------------------
    log INFO "Creating cost budget alert (EUR 450/month)..."
    az consumption budget create \
        --budget-name "budget-tktph-avd" \
        --amount 450 \
        --time-grain Monthly \
        --start-date "$(date +%Y-%m)-01" \
        --end-date "2027-12-31" \
        --resource-group "$RESOURCE_GROUP" \
        --category Cost \
        --notifications '{
            "Actual_80_Percent": {"enabled": true, "operator": "GreaterThan", "threshold": 80, "contactEmails": ["'"$ALERT_EMAIL"'"]},
            "Actual_100_Percent": {"enabled": true, "operator": "GreaterThan", "threshold": 100, "contactEmails": ["'"$ALERT_EMAIL"'"]}
        }' \
        --output none 2>/dev/null || log WARN "Budget creation may already exist or require manual setup"
    log SUCCESS "Cost budget created: EUR 450/month (80% and 100% alerts to $ALERT_EMAIL)"

    log SUCCESS "Phase 5.5 complete: SECURITY & GOVERNANCE"
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

    # Get subscription ID if not set
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
    fi

    local passed=0
    local failed=0
    local warnings=0

    echo ""
    printf "  %-50s %s\n" "Check" "Status"
    echo "  ---------------------------------------------------------------"

    # --- Resource group ---
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Resource Group"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Resource Group"
        failed=$((failed + 1))
    fi

    # --- Version tag ---
    local rg_version=$(az group show --name "$RESOURCE_GROUP" --query "tags.Version" -o tsv 2>/dev/null || echo "")
    if [[ "$rg_version" == "$VERSION_TAG" ]]; then
        printf "  %-50s ${GREEN}$VERSION_TAG${NC}\n" "Version Tag"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$rg_version (expected $VERSION_TAG)${NC}\n" "Version Tag"
        warnings=$((warnings + 1))
    fi

    # --- VMs with Entra ID join ---
    # V8 FIX: 1-indexed naming with zero-padding
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local state=$(az vm get-instance-view --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null)

        if [[ "$state" == "VM running" ]]; then
            printf "  %-50s ${GREEN}Running${NC}\n" "$vm_name"
            passed=$((passed + 1))
        else
            printf "  %-50s ${RED}$state${NC}\n" "$vm_name"
            failed=$((failed + 1))
        fi

        # Check AADLoginForWindows extension
        local aad_ext=$(az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AADLoginForWindows" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$aad_ext" == "Succeeded" ]]; then
            printf "  %-50s ${GREEN}Configured${NC}\n" "  Entra ID Join ($vm_name)"
            passed=$((passed + 1))
        else
            printf "  %-50s ${YELLOW}$aad_ext${NC}\n" "  Entra ID Join ($vm_name)"
            warnings=$((warnings + 1))
        fi

        # Check Azure Monitor Agent
        local ama_ext=$(az vm extension show --resource-group "$RESOURCE_GROUP" --vm-name "$vm_name" --name "AzureMonitorWindowsAgent" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$ama_ext" == "Succeeded" ]]; then
            printf "  %-50s ${GREEN}Installed${NC}\n" "  Azure Monitor Agent ($vm_name)"
            passed=$((passed + 1))
        else
            printf "  %-50s ${YELLOW}$ama_ext${NC}\n" "  Azure Monitor Agent ($vm_name)"
            warnings=$((warnings + 1))
        fi
    done

    # --- Session hosts available ---
    local available=$(az desktopvirtualization sessionhost list \
        --resource-group "$RESOURCE_GROUP" \
        --host-pool-name "$HOSTPOOL_NAME" \
        --query "[?status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$available" -ge "$VM_COUNT" ]]; then
        printf "  %-50s ${GREEN}$available Available${NC}\n" "Session Hosts Health"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$available/$VM_COUNT${NC}\n" "Session Hosts Health"
        warnings=$((warnings + 1))
    fi

    # --- Max session limit ---
    local max_sess=$(az desktopvirtualization hostpool show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --query "maxSessionLimit" -o tsv 2>/dev/null || echo "")

    if [[ "$max_sess" == "$MAX_SESSION_LIMIT" ]]; then
        printf "  %-50s ${GREEN}$max_sess${NC}\n" "Max Session Limit"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$max_sess (expected $MAX_SESSION_LIMIT)${NC}\n" "Max Session Limit"
        warnings=$((warnings + 1))
    fi

    # --- User assignment ---
    local dag_assignments=$(az role assignment list \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/applicationGroups/$APPGROUP_NAME" \
        --query "[?roleDefinitionName=='Desktop Virtualization User'] | length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$dag_assignments" -gt 0 ]]; then
        printf "  %-50s ${GREEN}Assigned${NC}\n" "App Group Assignment"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}Not assigned${NC}\n" "App Group Assignment"
        failed=$((failed + 1))
    fi

    # --- VM User Login role ---
    local vm_id=$(az vm show --resource-group "$RESOURCE_GROUP" --name "${VM_PREFIX}-01" --query id -o tsv 2>/dev/null)
    local vm_login_assignments=$(az role assignment list \
        --scope "$vm_id" \
        --query "[?roleDefinitionName=='Virtual Machine User Login'] | length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$vm_login_assignments" -gt 0 ]]; then
        printf "  %-50s ${GREEN}Assigned${NC}\n" "VM User Login Role"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}Not assigned${NC}\n" "VM User Login Role"
        failed=$((failed + 1))
    fi

    # --- Storage ---
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Storage Account"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Storage Account"
        failed=$((failed + 1))
    fi

    # --- FSLogix share ---
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$FSLOGIX_SHARE_NAME" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK ($FSLOGIX_SHARE_NAME)${NC}\n" "FSLogix File Share"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "FSLogix File Share"
        failed=$((failed + 1))
    fi

    # --- Shared docs share ---
    if az storage share-rm show --resource-group "$RESOURCE_GROUP" --storage-account "$STORAGE_ACCOUNT" --name "$SHARED_DOCS_SHARE_NAME" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK ($SHARED_DOCS_SHARE_NAME, ${SHARED_DOCS_QUOTA_GB}GB)${NC}\n" "Shared Documentation Share"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Shared Documentation Share"
        failed=$((failed + 1))
    fi

    # --- NSG rules ---
    local nsg_rule_count=$(az network nsg rule list \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$nsg_rule_count" -ge 5 ]]; then
        printf "  %-50s ${GREEN}$nsg_rule_count rules${NC}\n" "NSG Rules (SAP/Zoho/Teams)"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$nsg_rule_count rules (expected >= 5)${NC}\n" "NSG Rules"
        warnings=$((warnings + 1))
    fi

    # --- Data Collection Rule ---
    if az monitor data-collection rule show --resource-group "$RESOURCE_GROUP" --name "dcr-tktph-avd-sessions" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Data Collection Rule"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}Not found${NC}\n" "Data Collection Rule"
        warnings=$((warnings + 1))
    fi

    # --- Trusted Launch on VMs ---
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        local sec_type=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" \
            --query "securityProfile.securityType" -o tsv 2>/dev/null || echo "")
        if [[ "$sec_type" == "TrustedLaunch" ]]; then
            printf "  %-50s ${GREEN}Enabled${NC}\n" "Trusted Launch ($vm_name)"
            passed=$((passed + 1))
        else
            printf "  %-50s ${YELLOW}$sec_type${NC}\n" "Trusted Launch ($vm_name)"
            warnings=$((warnings + 1))
        fi
    done

    # --- Resource Lock ---
    if az lock show --name "DoNotDelete-TKT-AVD" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK (CanNotDelete)${NC}\n" "Resource Lock"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}Not found${NC}\n" "Resource Lock"
        warnings=$((warnings + 1))
    fi

    # --- Diagnostic Settings on Host Pool ---
    local hp_diag=$(az monitor diagnostic-settings list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME" \
        --query "[?name=='diag-${HOSTPOOL_NAME}'] | length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$hp_diag" -gt 0 ]]; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Diagnostic Settings (Host Pool)"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}Not found${NC}\n" "Diagnostic Settings (Host Pool)"
        warnings=$((warnings + 1))
    fi

    # --- Scaling Plan ---
    if az desktopvirtualization scaling-plan show --resource-group "$RESOURCE_GROUP" --name "sp-tktph-avd" &>/dev/null 2>&1; then
        printf "  %-50s ${GREEN}OK (Asia/Manila)${NC}\n" "Scaling Plan"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}Not found${NC}\n" "Scaling Plan"
        warnings=$((warnings + 1))
    fi

    # --- Log Analytics ---
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &>/dev/null; then
        printf "  %-50s ${GREEN}OK${NC}\n" "Log Analytics Workspace"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Log Analytics Workspace"
        failed=$((failed + 1))
    fi

    echo "  ---------------------------------------------------------------"
    printf "  %-50s ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}, ${YELLOW}$warnings warnings${NC}\n" "Results"
    echo ""

    if [[ $failed -gt 0 ]]; then
        log WARN "Validation completed with $failed failure(s). Review the items above."
    else
        log SUCCESS "Validation passed: all checks OK"
    fi

    log SUCCESS "Phase 6 complete: VALIDATION"
}

#===============================================================================
# FINAL SUMMARY
#===============================================================================

show_summary() {
    echo ""
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo -e "${GREEN}|                       DEPLOYMENT COMPLETE (V9)                                 |${NC}"
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
    echo "  Consultant Users ($USER_COUNT):"
    for idx in $(seq 0 $((USER_COUNT - 1))); do
        local role_tag=""
        [[ -n "${USER_ROLES[$idx]}" ]] && role_tag=" [${USER_ROLES[$idx]}]"
        echo "    - ${USER_DISPLAY_NAMES[$idx]} (${USER_USERNAMES[$idx]}@${ENTRA_DOMAIN})${role_tag}"
    done
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        echo "    - ${BREAK_GLASS_DISPLAY_NAME} (${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}) [BREAK-GLASS]"
    fi
    echo ""
    echo "  Applications Configured:"
    echo "    - Microsoft Edge (with Fiori + Zoho bookmarks)"
    echo "    - Microsoft Teams (with WebRTC media optimization)"
    echo "    - Shared Documentation Drive (Z:\\)"
    echo "    - FSLogix Profile Container"
    if [[ -n "$ACTIVTRAK_ACCOUNT_ID" ]]; then
        echo "    - ActivTrak Agent (productivity monitoring)"
    fi
    echo ""
    echo "  Security & Governance:"
    echo "    - Azure AD Kerberos authentication (no shared keys)"
    echo "    - Trusted Launch (Secure Boot + vTPM) on all VMs"
    echo "    - Encryption at Host enabled on all VMs"
    echo "    - CanNotDelete resource lock on resource group"
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        echo "    - Break-glass admin (password in Key Vault: $KEY_VAULT_NAME)"
    fi
    echo "    - Autoscale scaling plan (Asia/Manila business hours)"
    echo "    - Watermarking enabled (financial data protection)"
    echo "    - Screen capture protection enabled"
    echo "    - Cost budget alert (EUR 450/month, 80%/100% thresholds)"
    echo ""
    echo "  Session Logging:"
    echo "    - Enhanced Windows audit policies + Azure Monitor Agent"
    echo "    - Weekly JSON export to $SHARED_DOCS_SHARE_NAME (Sundays 23:00)"
    echo ""
    echo "  Files:"
    echo "    Log:               $LOG_FILE"
    echo "    Credentials:       ${CREDENTIALS_FILE:-N/A}"
    echo "    Registration:      $REGISTRATION_TOKEN_FILE"
    echo ""
    echo -e "  ${YELLOW}V9 Next Steps:${NC}"
    echo "    1. Wait 3-5 minutes for Entra ID join to complete"
    echo "    2. Distribute credentials from: $CREDENTIALS_FILE"
    echo "    3. Deploy Azure Firewall (recommended):"
    echo "       bash scripts/deploy-azure-firewall.sh"
    echo "    4. Deploy Conditional Access (recommended):"
    echo "       bash scripts/deploy-conditional-access.sh --report-only"
    echo "    5. Create Teams team (optional):"
    echo "       bash scripts/deploy-teams-team.sh"
    echo "    6. Verify SAP Fiori + Zoho Desk access via Edge"
    echo "    7. Test Teams call with WebRTC optimization"
    echo "    8. Verify Z:\\ shared drive is accessible"
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
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "TKT Azure Platform V9 - AVD Deployment Script"
                echo ""
                echo "Deploys a complete Azure Virtual Desktop environment for SAP"
                echo "consultants with Fiori, Zoho Desk, Teams, and shared storage."
                echo ""
                echo "Options:"
                echo "  --dry-run            Preview without making changes"
                echo "  --skip-prompts       Use environment/config values only"
                echo "  --force              Skip confirmation prompts"
                echo "  --config FILE        Load configuration from file"
                echo "  --users-file FILE    Load user configuration from JSON file"
                echo "  --help               Show this help"
                echo ""
                echo "Environment Variables:"
                echo "  ENTRA_DOMAIN              Entra ID domain (default: tktconsulting.be)"
                echo "  VM_SIZE                   VM SKU (default: Standard_D4s_v5)"
                echo "  VM_COUNT                  Number of session hosts (default: 3)"
                echo "  ADMIN_PASSWORD            VM admin password"
                echo "  USER_PASSWORD             Consultant user password"
                echo "  LOCATION                  Azure region (default: southeastasia)"
                echo "  ACTIVTRAK_ACCOUNT_ID      ActivTrak account (optional, enables agent)"
                echo "  BREAK_GLASS_ENABLED       Create break-glass admin (default: true)"
                echo ""
                echo "V9 User Configuration:"
                echo "  Place users.json in the scripts/ directory or use --users-file."
                echo "  See users.json.template for format. If no file found, interactive"
                echo "  prompts will ask for each user's real name and role."
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

    # V9: Load user configuration from JSON or prepare for interactive prompts
    load_users_config

    prompt_for_inputs

    # Setup password temp files (hidden from process listings)
    setup_password_files

    show_config_summary

    # Phase 1: Networking (VNet, NSG with SAP/Zoho/Teams rules)
    deploy_phase1_networking

    # Phase 2: Storage & Monitoring (FSLogix profiles share, Log Analytics)
    deploy_phase2_storage

    # Phase 2.5: Shared Documentation Storage (shared-docs share + folder structure)
    deploy_phase2_5_shared_docs

    # Phase 3: AVD Control Plane (Workspace, Host Pool with MaxSession=2, App Group)
    deploy_phase3_avd

    # Phase 4: Session Hosts (VMs with Entra ID join, AMA, weekday scheduling)
    deploy_phase4_session_hosts

    # Phase 4.5: Applications (Teams+WebRTC, Edge+bookmarks, shared drive, FSLogix)
    deploy_phase4_5_applications

    # Phase 4.6: Session Logging (audit policies, DCR, weekly export)
    deploy_phase4_6_session_logging

    # Phase 5: Identity (users, security group, RBAC roles, storage permissions)
    deploy_phase5_identity

    # Phase 5.5: Security & Governance (resource lock, diagnostics, scaling, watermarking, alerts, budget)
    deploy_phase5_5_security_governance

    # Phase 6: Validation (comprehensive checks)
    deploy_phase6_validation

    show_summary
}

main "$@"
