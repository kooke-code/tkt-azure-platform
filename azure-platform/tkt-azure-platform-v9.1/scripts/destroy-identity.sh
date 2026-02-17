#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9.1 Identity Destruction Script (Track A)
# Version: 9.1
# Date: 2026-02-17
#
# TRACK A TEARDOWN — Requires Global Admin (or User Administrator)
#
# Removes all Entra ID identity resources created by deploy-identity.sh:
#   - Entra ID users (from users.json or ph-consultant-001 through 006)
#   - Entra ID break-glass admin
#   - Entra ID security group
#   - Conditional Access policies (via Graph API)
#   - Named locations (via Graph API)
#   - Entra ID device records
#
# ORDER: Run destroy-infra.sh FIRST (Track B), THEN this script (Track A)
#
# USAGE:
#   bash destroy-identity.sh                    # Interactive
#   bash destroy-identity.sh --force            # Skip confirmation
#   bash destroy-identity.sh --dry-run          # Preview only
#===============================================================================

set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION
#===============================================================================

ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-6}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
BREAK_GLASS_USERNAME="${BREAK_GLASS_USERNAME:-tktph-breakglass}"
GRAPH_URL="https://graph.microsoft.com/v1.0"

DRY_RUN=false
FORCE=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load user config if available
declare -a USER_USERNAMES=()
if [[ -f "${SCRIPT_DIR}/users.json" ]] && command -v jq &>/dev/null; then
    local_domain=$(jq -r '.domain // empty' "${SCRIPT_DIR}/users.json" 2>/dev/null)
    [[ -n "$local_domain" ]] && ENTRA_DOMAIN="$local_domain"
    local_group=$(jq -r '.security_group // empty' "${SCRIPT_DIR}/users.json" 2>/dev/null)
    [[ -n "$local_group" ]] && SECURITY_GROUP_NAME="$local_group"
    local_count=$(jq '.users | length' "${SCRIPT_DIR}/users.json" 2>/dev/null)
    if [[ "$local_count" -gt 0 ]]; then
        USER_COUNT="$local_count"
        for i in $(seq 0 $((local_count - 1))); do
            USER_USERNAMES+=("$(jq -r ".users[$i].username" "${SCRIPT_DIR}/users.json")")
        done
    fi
    local_bg=$(jq -r '.break_glass.username // empty' "${SCRIPT_DIR}/users.json" 2>/dev/null)
    [[ -n "$local_bg" ]] && BREAK_GLASS_USERNAME="$local_bg"
fi

# Populate default usernames if not loaded from JSON
if [[ ${#USER_USERNAMES[@]} -eq 0 ]]; then
    for i in $(seq 1 $USER_COUNT); do
        USER_USERNAMES+=("${USER_PREFIX}-$(printf '%03d' $i)")
    done
fi

#===============================================================================
# COLORS & LOGGING
#===============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log() {
    local level="$1"; shift; local message="$*"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)    echo -e "${BLUE}[$ts] [INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$ts] [SUCCESS]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$ts] [WARN]${NC} $message" ;;
        ERROR)   echo -e "${RED}[$ts] [ERROR]${NC} $message" ;;
        DELETE)  echo -e "${RED}[$ts] [DELETE]${NC} $message" ;;
    esac
}

#===============================================================================
# PARSE ARGUMENTS
#===============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --force)    FORCE=true; shift ;;
        --domain)   ENTRA_DOMAIN="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash $0 [OPTIONS]"
            echo ""
            echo "TKT Azure Platform V9.1 - Identity Teardown (Track A)"
            echo ""
            echo "Options:"
            echo "  --dry-run    Preview what would be deleted"
            echo "  --force      Skip confirmation prompts"
            echo "  --domain D   Entra ID domain"
            echo "  --help       Show this help"
            echo ""
            echo "ORDER: Run destroy-infra.sh FIRST, then this script."
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

#===============================================================================
# PREREQUISITES
#===============================================================================

log INFO "Checking prerequisites..."
command -v az &>/dev/null || { log ERROR "Azure CLI not found."; exit 1; }
az account show &>/dev/null || { log ERROR "Not logged in. Run: az login"; exit 1; }
log SUCCESS "Prerequisites OK"

#===============================================================================
# BANNER & CONFIRMATION
#===============================================================================

echo ""
echo -e "${RED}+===============================================================================+${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}|         TKT Azure Platform V9.1 - IDENTITY DESTRUCTION (Track A)              |${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}|  This will PERMANENTLY DELETE all Entra ID users, groups, and CA policies     |${NC}"
echo -e "${RED}|  created by deploy-identity.sh. This action cannot be undone.                  |${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}+===============================================================================+${NC}"
echo ""

echo "  Users to delete:"
for uname in "${USER_USERNAMES[@]}"; do
    echo "    - ${uname}@${ENTRA_DOMAIN}"
done
echo "    - ${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN} (break-glass)"
echo ""
echo "  Group: $SECURITY_GROUP_NAME"
echo "  CA Policies: TKT-PH-AVD-Require-MFA, TKT-PH-AVD-Location-Restriction, TKT-PH-AVD-Block-Legacy-Auth"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}DRY RUN — No changes will be made${NC}"
    echo ""
    exit 0
fi

if [[ "$FORCE" != "true" ]]; then
    echo -e "  Type '${RED}DELETE IDENTITY${NC}' to confirm:"
    read -p "  > " confirmation
    if [[ "$confirmation" != "DELETE IDENTITY" ]]; then
        log INFO "Destruction cancelled."
        exit 0
    fi
    echo ""
    log WARN "Destruction confirmed. Starting in 3 seconds..."
    sleep 3
fi

#===============================================================================
# STEP 1: DELETE CONDITIONAL ACCESS POLICIES
#===============================================================================

log INFO "Step 1/5: Deleting Conditional Access policies..."

policy_names=("TKT-PH-AVD-Require-MFA" "TKT-PH-AVD-Location-Restriction" "TKT-PH-AVD-Block-Legacy-Auth")
for pname in "${policy_names[@]}"; do
    pid=$(az rest --method GET \
        --url "${GRAPH_URL}/identity/conditionalAccess/policies?\$filter=displayName eq '${pname}'" \
        --query "value[0].id" -o tsv 2>/dev/null || echo "")
    if [[ -n "$pid" && "$pid" != "null" ]]; then
        az rest --method DELETE --url "${GRAPH_URL}/identity/conditionalAccess/policies/${pid}" 2>/dev/null || true
        log DELETE "Deleted CA policy: $pname"
    fi
done

# Delete named locations
for loc_name in "Philippines" "Belgium"; do
    lid=$(az rest --method GET \
        --url "${GRAPH_URL}/identity/conditionalAccess/namedLocations?\$filter=displayName eq '${loc_name}'" \
        --query "value[0].id" -o tsv 2>/dev/null || echo "")
    if [[ -n "$lid" && "$lid" != "null" ]]; then
        az rest --method DELETE --url "${GRAPH_URL}/identity/conditionalAccess/namedLocations/${lid}" 2>/dev/null || true
        log DELETE "Deleted named location: $loc_name"
    fi
done
log SUCCESS "Conditional Access policies cleaned up"

#===============================================================================
# STEP 2: DELETE USERS
#===============================================================================

log INFO "Step 2/5: Deleting Entra ID users..."

for uname in "${USER_USERNAMES[@]}"; do
    upn="${uname}@${ENTRA_DOMAIN}"
    if az ad user show --id "$upn" &>/dev/null 2>&1; then
        log DELETE "Deleting user: $upn"
        az ad user delete --id "$upn" 2>/dev/null || log WARN "Could not delete $upn"
    else
        log INFO "User $upn not found (already deleted)"
    fi
done
log SUCCESS "Users deleted"

#===============================================================================
# STEP 3: DELETE BREAK-GLASS ADMIN
#===============================================================================

log INFO "Step 3/5: Deleting break-glass admin..."
bg_upn="${BREAK_GLASS_USERNAME}@${ENTRA_DOMAIN}"
if az ad user show --id "$bg_upn" &>/dev/null 2>&1; then
    az ad user delete --id "$bg_upn" 2>/dev/null || true
    log DELETE "Deleted break-glass admin: $bg_upn"
else
    log INFO "Break-glass admin not found (skipping)"
fi

#===============================================================================
# STEP 4: DELETE SECURITY GROUP
#===============================================================================

log INFO "Step 4/5: Deleting security group..."
group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "")
if [[ -n "$group_id" ]]; then
    log DELETE "Deleting security group: $SECURITY_GROUP_NAME"
    az ad group delete --group "$group_id" 2>/dev/null || log WARN "Could not delete security group"
else
    log INFO "Security group not found (already deleted)"
fi

#===============================================================================
# STEP 5: CLEAN UP DEVICE RECORDS
#===============================================================================

log INFO "Step 5/5: Cleaning up Entra ID device records..."
devices=$(az rest --method GET \
    --url "https://graph.microsoft.com/v1.0/devices?\$filter=startswith(displayName,'vm-tktph')" \
    --query "value[].{id:id,name:displayName}" -o tsv 2>/dev/null || echo "")

if [[ -n "$devices" ]]; then
    echo "$devices" | while IFS=$'\t' read -r device_id device_name; do
        if [[ -n "$device_id" ]]; then
            log DELETE "Removing Entra ID device: $device_name ($device_id)"
            az rest --method DELETE --url "https://graph.microsoft.com/v1.0/devices/${device_id}" 2>/dev/null || true
        fi
    done
fi
log SUCCESS "Entra ID device records cleaned up"

#===============================================================================
# SUMMARY
#===============================================================================

echo ""
echo -e "${RED}+===============================================================================+${NC}"
echo -e "${RED}|              IDENTITY DESTRUCTION COMPLETE (Track A)                           |${NC}"
echo -e "${RED}+===============================================================================+${NC}"
echo ""
echo "  Deleted: $USER_COUNT users, break-glass admin, security group"
echo "  Deleted: 3 Conditional Access policies, 2 named locations"
echo "  Cleaned: Entra ID device records"
echo ""
