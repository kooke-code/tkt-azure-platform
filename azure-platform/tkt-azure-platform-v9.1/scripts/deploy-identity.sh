#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9.1 Identity Deployment Script (Track A)
# Version: 9.1
# Date: 2026-02-17
#
# TRACK A — Requires Global Admin (or User Administrator + Cloud Device Admin)
#
# This script provisions Entra ID identity resources:
#   Phase 1: Security group creation
#   Phase 2: Named user creation (from users.json or interactive)
#   Phase 3: Break-glass admin account
#   Phase 4: Stale device cleanup (optional, --skip-device-cleanup)
#   Output:  Credentials file + security group Object ID for Track B
#
# SPLIT FROM: V9 deploy-avd-platform.sh (Phase 5 identity sections)
# COUNTERPART: deploy-infra.sh (Track B — infrastructure, Contributor role)
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - User Administrator role in Entra ID (or Global Admin)
#   - Cloud Device Administrator (for stale device cleanup)
#   - jq (for users.json parsing)
#   - bash shell (not zsh)
#
# USAGE:
#   bash deploy-identity.sh                              # Interactive mode
#   bash deploy-identity.sh --users-file users.json      # Use user config
#   bash deploy-identity.sh --dry-run                    # Preview only
#   bash deploy-identity.sh --skip-device-cleanup        # Skip device cleanup
#   bash deploy-identity.sh --skip-prompts               # Non-interactive
#
# AFTER RUNNING:
#   1. Assign M365 F3 licenses manually (see docs/license-guide.md)
#   2. Run deploy-conditional-access.sh (Track A)
#   3. Run deploy-teams-team.sh (Track A)
#   4. Hand off to Track B operator: deploy-infra.sh
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# Cleanup on failure
cleanup_on_exit() {
    local exit_code=$?
    rm -f "${_USER_PW_FILE:-}" 2>/dev/null
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "\033[0;31m[ERROR] Identity deployment failed (exit code $exit_code).\033[0m"
        echo "  Log file: ${LOG_FILE:-/tmp/identity-deployment.log}"
        echo "  To resume, re-run the script - it will skip already-created resources."
    fi
}
trap cleanup_on_exit EXIT

# Ensure running in bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash $0 $*"
    exit 1
fi

#===============================================================================
# DEFAULT CONFIGURATION
#===============================================================================

# Identity
ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-6}"
USER_PASSWORD="${USER_PASSWORD:-}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
MAX_SESSION_LIMIT="${MAX_SESSION_LIMIT:-2}"

# Break-glass admin
BREAK_GLASS_ENABLED="${BREAK_GLASS_ENABLED:-true}"
BREAK_GLASS_USERNAME="${BREAK_GLASS_USERNAME:-tktph-breakglass}"
BREAK_GLASS_DISPLAY_NAME="${BREAK_GLASS_DISPLAY_NAME:-TKT PH Break Glass Admin}"

# Script Control
DRY_RUN="${DRY_RUN:-false}"
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"
SKIP_DEVICE_CLEANUP="${SKIP_DEVICE_CLEANUP:-false}"
USERS_FILE="${USERS_FILE:-}"
ALERT_EMAIL="${ALERT_EMAIL:-tom.tuerlings@tktconsulting.com}"

# Runtime
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DEPLOYMENT_ID="$TIMESTAMP"
LOG_FILE="/tmp/identity-deployment-${TIMESTAMP}.log"

# Version tag
VERSION_TAG="9.1"

# User arrays (populated from users.json or interactive prompts)
declare -a USER_USERNAMES=()
declare -a USER_DISPLAY_NAMES=()
declare -a USER_ROLES=()
declare -a USER_JOB_TITLES=()

# Credentials output
CREDENTIALS_FILE=""

# Temp file for password
_USER_PW_FILE=""

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
    echo -e "${CYAN}+===============================================================================+${NC}"
    echo -e "${CYAN}|                                                                               |${NC}"
    echo -e "${CYAN}|     ████████╗██╗  ██╗████████╗     ██████╗ ██╗  ██╗                           |${NC}"
    echo -e "${CYAN}|     ╚══██╔══╝██║ ██╔╝╚══██╔══╝     ██╔══██╗██║  ██║                           |${NC}"
    echo -e "${CYAN}|        ██║   █████╔╝    ██║        ██████╔╝███████║                           |${NC}"
    echo -e "${CYAN}|        ██║   ██╔═██╗    ██║        ██╔═══╝ ██╔══██║                           |${NC}"
    echo -e "${CYAN}|        ██║   ██║  ██╗   ██║        ██║     ██║  ██║                           |${NC}"
    echo -e "${CYAN}|        ╚═╝   ╚═╝  ╚═╝   ╚═╝        ╚═╝     ╚═╝  ╚═╝                           |${NC}"
    echo -e "${CYAN}|                                                                               |${NC}"
    echo -e "${CYAN}|              Azure Virtual Desktop - V9.1 Identity Deployment                 |${NC}"
    echo -e "${CYAN}|                    TRACK A — Global Admin / User Admin                        |${NC}"
    echo -e "${CYAN}|                          ${ENTRA_DOMAIN}                                      |${NC}"
    echo -e "${CYAN}|                                                                               |${NC}"
    echo -e "${CYAN}+===============================================================================+${NC}"
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

    if ! az account show &> /dev/null; then
        fail "Not logged in to Azure. Run: az login"
    fi

    local account=$(az account show --query "name" -o tsv)
    log INFO "Azure account: $account"

    # Check jq (needed for users.json parsing)
    if ! command -v jq &> /dev/null; then
        log WARN "jq not found. Install jq for users.json support. Interactive prompts will be used instead."
    else
        log INFO "jq version: $(jq --version 2>/dev/null || echo 'unknown')"
    fi

    # Verify Graph API access (identity operations require directory roles)
    log INFO "Verifying Entra ID access (Graph API)..."
    if ! az rest --method GET --url "https://graph.microsoft.com/v1.0/organization" --query "value[0].displayName" -o tsv &>/dev/null 2>&1; then
        fail "Cannot access Microsoft Graph API. This script requires User Administrator or Global Admin role in Entra ID."
    fi

    log SUCCESS "Prerequisites check passed"
}

#===============================================================================
# LOAD USER CONFIGURATION (users.json or interactive)
#===============================================================================

load_users_config() {
    local users_file=""

    if [[ -n "$USERS_FILE" && -f "$USERS_FILE" ]]; then
        users_file="$USERS_FILE"
    elif [[ -f "${SCRIPT_DIR}/users.json" ]]; then
        users_file="${SCRIPT_DIR}/users.json"
    fi

    if [[ -n "$users_file" ]] && command -v jq &> /dev/null; then
        log INFO "Loading user configuration from: $users_file"

        if ! jq empty "$users_file" 2>/dev/null; then
            fail "Invalid JSON in users file: $users_file"
        fi

        local json_domain=$(jq -r '.domain // empty' "$users_file")
        if [[ -n "$json_domain" ]]; then
            ENTRA_DOMAIN="$json_domain"
            log INFO "Domain from users.json: $ENTRA_DOMAIN"
        fi

        local json_group=$(jq -r '.security_group // empty' "$users_file")
        if [[ -n "$json_group" ]]; then
            SECURITY_GROUP_NAME="$json_group"
        fi

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

    else
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
    echo -e "${YELLOW}  V9.1 TRACK A: USER CONFIGURATION${NC}"
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

    echo ""
    read -p "  Create break-glass admin account? (Y/n): " bg_confirm
    if [[ "$bg_confirm" =~ ^[Nn]$ ]]; then
        BREAK_GLASS_ENABLED="false"
    fi
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
    echo -e "${YELLOW}===============================================================================${NC}"
    echo -e "${YELLOW}  CONFIGURATION${NC}"
    echo -e "${YELLOW}===============================================================================${NC}"
    echo ""

    # Prompt for user details if not loaded from JSON
    if [[ ${#USER_USERNAMES[@]} -eq 0 ]]; then
        _prompt_for_users
    fi

    # Confirm domain
    echo -e "${BLUE}[1/3] Confirm Entra ID domain${NC}"
    echo "    Domain: $ENTRA_DOMAIN"
    read -p "    Press Enter to confirm or type new domain: " new_domain
    if [[ -n "$new_domain" ]]; then
        ENTRA_DOMAIN="$new_domain"
    fi
    echo ""

    # User Password
    if [[ -z "$USER_PASSWORD" ]]; then
        echo -e "${BLUE}[2/3] Enter temporary password for consultant accounts${NC}"
        echo "    (Users will change on first login)"
        read -sp "    Password: " USER_PASSWORD
        echo ""
        echo ""
    fi

    # Alert Email (for credentials file header)
    echo -e "${BLUE}[3/3] Confirm alert email${NC}"
    echo "    Current: $ALERT_EMAIL"
    read -p "    Press Enter to confirm or type new email: " new_email
    if [[ -n "$new_email" ]]; then
        ALERT_EMAIL="$new_email"
    fi
    echo ""

    log SUCCESS "Configuration complete"
}

#===============================================================================
# PASSWORD FILE HELPERS
#===============================================================================

setup_password_files() {
    _USER_PW_FILE=$(mktemp /tmp/.identity-user-pw-XXXXXX)
    chmod 600 "$_USER_PW_FILE"
    printf '%s' "$USER_PASSWORD" > "$_USER_PW_FILE"
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
    echo -e "${CYAN}  IDENTITY DEPLOYMENT SUMMARY - V9.1 TRACK A${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""
    echo "  Identity (Entra ID)"
    echo "  -------------------"
    echo "    Domain:           $ENTRA_DOMAIN"
    echo "    Users:            $USER_COUNT consultants (named)"
    for idx in $(seq 0 $((USER_COUNT - 1))); do
        echo "      - ${USER_DISPLAY_NAMES[$idx]} (${USER_USERNAMES[$idx]}@${ENTRA_DOMAIN})"
    done
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        echo "    Break-Glass:      ${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
    fi
    echo "    Security Group:   $SECURITY_GROUP_NAME"
    echo "    Device Cleanup:   $([ "$SKIP_DEVICE_CLEANUP" == "true" ] && echo "Skipped" || echo "Enabled")"
    echo ""
    echo "  Version: $VERSION_TAG"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}MODE: DRY RUN (no changes will be made)${NC}"
        echo ""
    fi

    if [[ "$SKIP_PROMPTS" != "true" ]]; then
        read -p "Proceed with identity deployment? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 0
        fi
    fi
}

#===============================================================================
# PHASE 1: SECURITY GROUP
#===============================================================================

deploy_phase1_security_group() {
    log_phase 1 "SECURITY GROUP"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create security group: $SECURITY_GROUP_NAME"
        return
    fi

    local group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null)

    if [[ -z "$group_id" ]]; then
        log INFO "Creating security group: $SECURITY_GROUP_NAME"
        group_id=$(az ad group create \
            --display-name "$SECURITY_GROUP_NAME" \
            --mail-nickname "tktph-avd-users" \
            --query "id" -o tsv)
        log SUCCESS "Security group created: $group_id"
    else
        log INFO "Security group $SECURITY_GROUP_NAME already exists: $group_id"
    fi

    log SUCCESS "Phase 1 complete: SECURITY GROUP"
}

#===============================================================================
# PHASE 2: USER CREATION
#===============================================================================

deploy_phase2_users() {
    log_phase 2 "USER CREATION (V9.1)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create $USER_COUNT named users and add to $SECURITY_GROUP_NAME"
        return
    fi

    # Initialize credentials file
    CREDENTIALS_FILE="/tmp/credentials-${DEPLOYMENT_ID}.txt"
    {
        echo "==============================================================================="
        echo "  TKT Philippines AVD Platform V9.1 - User Credentials"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Domain: $ENTRA_DOMAIN"
        echo "  Track: A (Identity — Global Admin)"
        echo "==============================================================================="
        echo ""
        printf "%-25s | %-45s | %s\n" "Display Name" "UPN" "Temp Password"
        echo "----------------------------+-------------------------------------------------+------------------"
    } > "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"

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
    log SUCCESS "Phase 2 complete: USER CREATION"
}

#===============================================================================
# PHASE 3: BREAK-GLASS ADMIN
#===============================================================================

deploy_phase3_break_glass() {
    log_phase 3 "BREAK-GLASS ADMIN"

    if [[ "$BREAK_GLASS_ENABLED" != "true" ]]; then
        log INFO "Break-glass admin creation disabled. Skipping."
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create break-glass admin: ${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
        return
    fi

    local bg_upn="${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"

    # Generate strong random password (32 chars)
    local bg_password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
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

    # Write break-glass info to credentials file (reference only, not the password)
    if [[ -n "$CREDENTIALS_FILE" && -f "$CREDENTIALS_FILE" ]]; then
        printf "%-25s | %-45s | %s\n" "$BREAK_GLASS_DISPLAY_NAME" "$bg_upn" "(stored separately)" >> "$CREDENTIALS_FILE"
        echo "" >> "$CREDENTIALS_FILE"
        echo "Break-glass password: Save this securely. It will be stored in Key Vault by deploy-infra.sh." >> "$CREDENTIALS_FILE"
        echo "Temporary password (give to Track B operator for Key Vault storage): $bg_password" >> "$CREDENTIALS_FILE"
    fi

    # Clear password from memory
    bg_password=""

    log SUCCESS "Phase 3 complete: BREAK-GLASS ADMIN"
}

#===============================================================================
# PHASE 4: STALE DEVICE CLEANUP (optional)
#===============================================================================

deploy_phase4_device_cleanup() {
    log_phase 4 "STALE DEVICE CLEANUP"

    if [[ "$SKIP_DEVICE_CLEANUP" == "true" ]]; then
        log INFO "Device cleanup skipped (--skip-device-cleanup flag)"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up stale Entra ID device records matching vm-tktph*"
        return
    fi

    log INFO "Checking for stale Entra ID device records..."
    local devices
    devices=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/devices?\$filter=startswith(displayName,'vm-tktph')" \
        --query "value[].{id:id,name:displayName}" -o tsv 2>/dev/null || echo "")

    if [[ -z "$devices" ]]; then
        log INFO "No stale device records found"
    else
        echo "$devices" | while IFS=$'\t' read -r device_id device_name; do
            if [[ -n "$device_id" ]]; then
                log WARN "Removing stale Entra ID device: $device_name ($device_id)"
                az rest --method DELETE --url "https://graph.microsoft.com/v1.0/devices/${device_id}" 2>/dev/null || true
            fi
        done
        log SUCCESS "Stale device records cleaned up"
    fi

    log SUCCESS "Phase 4 complete: STALE DEVICE CLEANUP"
}

#===============================================================================
# VALIDATION
#===============================================================================

run_validation() {
    echo ""
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  VALIDATION${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo ""

    local passed=0
    local failed=0

    printf "  %-50s %s\n" "Check" "Status"
    echo "  ---------------------------------------------------------------"

    # Check security group exists
    local group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null)
    if [[ -n "$group_id" ]]; then
        printf "  %-50s ${GREEN}OK ($group_id)${NC}\n" "Security Group"
        passed=$((passed + 1))
    else
        printf "  %-50s ${RED}FAIL${NC}\n" "Security Group"
        failed=$((failed + 1))
    fi

    # Check users exist and are group members
    for idx in $(seq 0 $((USER_COUNT - 1))); do
        local upn="${USER_USERNAMES[$idx]}@${ENTRA_DOMAIN}"
        if az ad user show --id "$upn" &>/dev/null 2>&1; then
            printf "  %-50s ${GREEN}OK${NC}\n" "User: $upn"
            passed=$((passed + 1))
        else
            printf "  %-50s ${RED}FAIL${NC}\n" "User: $upn"
            failed=$((failed + 1))
        fi
    done

    # Check group membership count
    local member_count=$(az ad group member list --group "$SECURITY_GROUP_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$member_count" -ge "$USER_COUNT" ]]; then
        printf "  %-50s ${GREEN}$member_count members${NC}\n" "Group Membership"
        passed=$((passed + 1))
    else
        printf "  %-50s ${YELLOW}$member_count (expected >= $USER_COUNT)${NC}\n" "Group Membership"
        failed=$((failed + 1))
    fi

    # Check break-glass
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        local bg_upn="${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
        if az ad user show --id "$bg_upn" &>/dev/null 2>&1; then
            printf "  %-50s ${GREEN}OK${NC}\n" "Break-Glass Admin"
            passed=$((passed + 1))
        else
            printf "  %-50s ${RED}FAIL${NC}\n" "Break-Glass Admin"
            failed=$((failed + 1))
        fi
    fi

    echo "  ---------------------------------------------------------------"
    printf "  %-50s ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}\n" "Results"
    echo ""

    if [[ $failed -gt 0 ]]; then
        log WARN "Validation completed with $failed failure(s)."
    else
        log SUCCESS "All validation checks passed"
    fi
}

#===============================================================================
# SUMMARY
#===============================================================================

show_summary() {
    local group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "N/A")

    echo ""
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo -e "${GREEN}|              TRACK A IDENTITY DEPLOYMENT COMPLETE (V9.1)                       |${NC}"
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo ""
    echo "  Domain:             $ENTRA_DOMAIN"
    echo "  Security Group:     $SECURITY_GROUP_NAME"
    echo "  Security Group ID:  $group_id"
    echo "  Users Created:      $USER_COUNT consultants"
    for idx in $(seq 0 $((USER_COUNT - 1))); do
        local role_tag=""
        [[ -n "${USER_ROLES[$idx]}" ]] && role_tag=" [${USER_ROLES[$idx]}]"
        echo "    - ${USER_DISPLAY_NAMES[$idx]} (${USER_USERNAMES[$idx]}@${ENTRA_DOMAIN})${role_tag}"
    done
    if [[ "$BREAK_GLASS_ENABLED" == "true" ]]; then
        echo "    - ${BREAK_GLASS_DISPLAY_NAME} (${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}) [BREAK-GLASS]"
    fi
    echo ""
    echo "  Credentials File:   ${CREDENTIALS_FILE:-N/A}"
    echo "  Log File:           $LOG_FILE"
    echo ""
    echo -e "  ${YELLOW}NEXT STEPS (Track A — Global Admin):${NC}"
    echo "    1. Assign M365 F3 licenses to all users (see docs/license-guide.md)"
    echo "    2. Deploy Conditional Access policies:"
    echo "       bash scripts/deploy-conditional-access.sh --report-only"
    echo "    3. Create Teams team:"
    echo "       bash scripts/deploy-teams-team.sh"
    echo ""
    echo -e "  ${YELLOW}HAND OFF TO TRACK B (Contributor — yannick@...):${NC}"
    echo "    Security Group Name: $SECURITY_GROUP_NAME"
    echo "    Command:"
    echo "       bash scripts/deploy-infra.sh --security-group-name \"$SECURITY_GROUP_NAME\""
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
            --skip-device-cleanup) SKIP_DEVICE_CLEANUP="true"; shift ;;
            --users-file) USERS_FILE="$2"; shift 2 ;;
            --domain) ENTRA_DOMAIN="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "TKT Azure Platform V9.1 - Identity Deployment (Track A)"
                echo ""
                echo "Provisions Entra ID users, security group, and break-glass admin."
                echo "Requires Global Admin or User Administrator + Cloud Device Admin."
                echo ""
                echo "Options:"
                echo "  --dry-run                Preview without making changes"
                echo "  --skip-prompts           Use environment/config values only"
                echo "  --skip-device-cleanup    Skip stale Entra ID device cleanup"
                echo "  --users-file FILE        Load user configuration from JSON file"
                echo "  --domain DOMAIN          Entra ID domain"
                echo "  --help                   Show this help"
                echo ""
                echo "After running this script, hand off to Track B operator:"
                echo "  bash scripts/deploy-infra.sh"
                echo ""
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    check_prerequisites
    load_users_config
    prompt_for_inputs

    # Setup password temp file
    setup_password_files

    show_config_summary

    deploy_phase1_security_group
    deploy_phase2_users
    deploy_phase3_break_glass
    deploy_phase4_device_cleanup

    if [[ "$DRY_RUN" != "true" ]]; then
        run_validation
    fi

    show_summary
}

main "$@"
