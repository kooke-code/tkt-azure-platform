#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9 Conditional Access Deployment
# Version: 9.0
# Date: 2026-02-17
#
# Deploys Conditional Access policies for TKT Philippines AVD platform using
# Microsoft Graph REST API (az rest). Converted from V7 PowerShell to bash.
#
# Policies created:
#   1. TKT-PH-AVD-Require-MFA         - MFA for AVD access (8-hour sign-in frequency)
#   2. TKT-PH-AVD-Location-Restriction - Block access outside Philippines + Belgium
#   3. TKT-PH-AVD-Block-Legacy-Auth   - Block legacy authentication protocols
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Conditional Access Administrator or Global Administrator role
#   - jq (for JSON parsing)
#
# USAGE:
#   bash deploy-conditional-access.sh                   # Report-only mode (default)
#   bash deploy-conditional-access.sh --enforce         # Enforce policies
#   bash deploy-conditional-access.sh --dry-run         # Preview only
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

#===============================================================================
# DEFAULTS
#===============================================================================

SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
AVD_APP_ID="9cdead84-a844-4324-93f2-b2e6bb768d07"
GLOBAL_ADMIN_ROLE_ID="62e90394-69f5-4237-9190-012177145e10"
BREAK_GLASS_UPN="${BREAK_GLASS_UPN:-}"
VERSION_TAG="9.0"

POLICY_STATE="enabledForReportingButNotEnforced"
ENFORCE_MODE="false"
DRY_RUN="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="/tmp/avd-ca-deployment-${TIMESTAMP}.log"

GRAPH_URL="https://graph.microsoft.com/v1.0"

#===============================================================================
# COLORS & LOGGING
#===============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() {
    local level="$1"; shift; local message="$*"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)    echo -e "${BLUE}[$ts] [INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$ts] [SUCCESS]${NC} $message" ;;
        WARN)    echo -e "${YELLOW}[$ts] [WARN]${NC} $message" ;;
        ERROR)   echo -e "${RED}[$ts] [ERROR]${NC} $message" ;;
        PHASE)   echo -e "${CYAN}[$ts] [PHASE]${NC} $message" ;;
    esac
    echo "[$ts] [$level] $message" >> "$LOG_FILE"
}

log_phase() {
    echo ""; echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${CYAN}  PHASE $1: $2${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    log PHASE "Starting Phase $1: $2"
}

fail() { log ERROR "$1"; exit 1; }

#===============================================================================
# HELPERS
#===============================================================================

create_or_find_named_location() {
    local display_name="$1" country_code="$2"

    local existing_id=$(az rest --method GET \
        --url "${GRAPH_URL}/identity/conditionalAccess/namedLocations?\$filter=displayName eq '${display_name}'" \
        --query "value[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
        log INFO "Named location '$display_name' already exists ($existing_id)"
        echo "$existing_id"; return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create named location: $display_name ($country_code)"
        echo "dry-run-id"; return
    fi

    local body=$(jq -n --arg name "$display_name" --arg code "$country_code" '{
        "@odata.type": "#microsoft.graph.countryNamedLocation",
        "displayName": $name, "countriesAndRegions": [$code],
        "includeUnknownCountriesAndRegions": false
    }')

    local new_id=$(az rest --method POST \
        --url "${GRAPH_URL}/identity/conditionalAccess/namedLocations" \
        --body "$body" --headers "Content-Type=application/json" \
        --query "id" -o tsv 2>/dev/null)

    [[ -n "$new_id" ]] && { log SUCCESS "Created: $display_name ($new_id)"; echo "$new_id"; } \
        || fail "Failed to create named location: $display_name"
}

create_or_find_policy() {
    local policy_name="$1" policy_body="$2"

    local existing_id=$(az rest --method GET \
        --url "${GRAPH_URL}/identity/conditionalAccess/policies?\$filter=displayName eq '${policy_name}'" \
        --query "value[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
        log INFO "Policy '$policy_name' already exists ($existing_id)"; return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create policy: $policy_name"; return 0
    fi

    az rest --method POST \
        --url "${GRAPH_URL}/identity/conditionalAccess/policies" \
        --body "$policy_body" --headers "Content-Type=application/json" \
        --output none 2>/dev/null \
        || { log ERROR "Failed to create policy: $policy_name"; return 1; }

    log SUCCESS "Created policy: $policy_name"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo -e "${CYAN}+===============================================================================+${NC}"
    echo -e "${CYAN}|       TKT Philippines AVD - Conditional Access Deployment (V9)                 |${NC}"
    echo -e "${CYAN}+===============================================================================+${NC}"
    echo ""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enforce) ENFORCE_MODE="true"; POLICY_STATE="enabled"; shift ;;
            --report-only) POLICY_STATE="enabledForReportingButNotEnforced"; shift ;;
            --dry-run) DRY_RUN="true"; shift ;;
            --security-group) SECURITY_GROUP_NAME="$2"; shift 2 ;;
            --break-glass-upn) BREAK_GLASS_UPN="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo "  --report-only       Report-only mode (default)"
                echo "  --enforce           Enforce policies immediately"
                echo "  --dry-run           Preview only"
                echo "  --security-group N  Security group name"
                echo "  --break-glass-upn U Break-glass UPN to exclude"
                exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Prerequisites
    log INFO "Checking prerequisites..."
    command -v az &>/dev/null || fail "Azure CLI not found"
    command -v jq &>/dev/null || fail "jq not found. Install: brew install jq"
    az account show &>/dev/null || fail "Not logged in. Run: az login"
    az rest --method GET --url "${GRAPH_URL}/organization" --query "value[0].displayName" -o tsv &>/dev/null \
        || fail "Cannot access Microsoft Graph. Need Conditional Access Administrator role."
    log SUCCESS "Prerequisites passed"

    # Auto-detect break-glass from users.json
    if [[ -z "$BREAK_GLASS_UPN" && -f "${SCRIPT_DIR}/users.json" ]]; then
        local bg_user=$(jq -r '.break_glass.username // empty' "${SCRIPT_DIR}/users.json")
        local bg_domain=$(jq -r '.domain // "tktconsulting.be"' "${SCRIPT_DIR}/users.json")
        [[ -n "$bg_user" ]] && BREAK_GLASS_UPN="${bg_user}@${bg_domain}" \
            && log INFO "Auto-detected break-glass: $BREAK_GLASS_UPN"
    fi

    # Look up security group
    local group_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query "id" -o tsv 2>/dev/null)
    [[ -z "$group_id" ]] && fail "Security group '$SECURITY_GROUP_NAME' not found"
    log SUCCESS "Security group: $group_id"

    # Look up break-glass user
    local bg_user_id=""
    if [[ -n "$BREAK_GLASS_UPN" ]]; then
        bg_user_id=$(az ad user show --id "$BREAK_GLASS_UPN" --query "id" -o tsv 2>/dev/null || echo "")
        [[ -n "$bg_user_id" ]] && log INFO "Break-glass: $BREAK_GLASS_UPN ($bg_user_id)" \
            || log WARN "Break-glass user not found — will not be excluded"
    fi

    local exclude_users="[]"
    [[ -n "$bg_user_id" ]] && exclude_users="[\"${bg_user_id}\"]"

    echo ""
    [[ "$ENFORCE_MODE" == "true" ]] \
        && echo -e "  ${RED}MODE: ENFORCED${NC}" \
        || echo -e "  ${YELLOW}MODE: REPORT-ONLY${NC}"
    echo ""

    # =====================================================================
    # PHASE 1: Named Locations
    # =====================================================================
    log_phase 1 "NAMED LOCATIONS"
    local ph_id=$(create_or_find_named_location "Philippines" "PH")
    local be_id=$(create_or_find_named_location "Belgium" "BE")
    log SUCCESS "Phase 1 complete"

    # =====================================================================
    # PHASE 2: Require MFA
    # =====================================================================
    log_phase 2 "REQUIRE MFA"

    local mfa_body=$(jq -n \
        --arg name "TKT-PH-AVD-Require-MFA" \
        --arg state "$POLICY_STATE" \
        --arg app "$AVD_APP_ID" \
        --arg grp "$group_id" \
        --arg role "$GLOBAL_ADMIN_ROLE_ID" \
        --argjson excl "$exclude_users" \
        '{
            "displayName": $name, "state": $state,
            "conditions": {
                "applications": {"includeApplications": [$app]},
                "users": {"includeGroups": [$grp], "excludeRoles": [$role], "excludeUsers": $excl},
                "clientAppTypes": ["browser","mobileAppsAndDesktopClients"]
            },
            "grantControls": {"operator":"OR","builtInControls":["mfa"]},
            "sessionControls": {"signInFrequency":{"value":8,"type":"hours","isEnabled":true}}
        }')
    create_or_find_policy "TKT-PH-AVD-Require-MFA" "$mfa_body"
    log SUCCESS "Phase 2 complete"

    # =====================================================================
    # PHASE 3: Location Restriction
    # =====================================================================
    log_phase 3 "LOCATION RESTRICTION"

    local loc_body=$(jq -n \
        --arg name "TKT-PH-AVD-Location-Restriction" \
        --arg state "$POLICY_STATE" \
        --arg app "$AVD_APP_ID" \
        --arg grp "$group_id" \
        --arg role "$GLOBAL_ADMIN_ROLE_ID" \
        --arg ph "$ph_id" --arg be "$be_id" \
        --argjson excl "$exclude_users" \
        '{
            "displayName": $name, "state": $state,
            "conditions": {
                "applications": {"includeApplications": [$app]},
                "users": {"includeGroups": [$grp], "excludeRoles": [$role], "excludeUsers": $excl},
                "locations": {"includeLocations": ["All"], "excludeLocations": [$ph, $be]}
            },
            "grantControls": {"operator":"OR","builtInControls":["block"]}
        }')
    create_or_find_policy "TKT-PH-AVD-Location-Restriction" "$loc_body"
    log SUCCESS "Phase 3 complete"

    # =====================================================================
    # PHASE 4: Block Legacy Auth (always enforced)
    # =====================================================================
    log_phase 4 "BLOCK LEGACY AUTH"

    local legacy_body=$(jq -n \
        --arg name "TKT-PH-AVD-Block-Legacy-Auth" \
        --arg grp "$group_id" \
        '{
            "displayName": $name, "state": "enabled",
            "conditions": {
                "applications": {"includeApplications": ["All"]},
                "users": {"includeGroups": [$grp]},
                "clientAppTypes": ["exchangeActiveSync","other"]
            },
            "grantControls": {"operator":"OR","builtInControls":["block"]}
        }')
    create_or_find_policy "TKT-PH-AVD-Block-Legacy-Auth" "$legacy_body"
    log SUCCESS "Phase 4 complete"

    # =====================================================================
    # PHASE 5: Summary
    # =====================================================================
    log_phase 5 "VALIDATION"

    echo ""
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo -e "${GREEN}|              Conditional Access Deployment Complete (V9)                       |${NC}"
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo ""
    echo "  Named Locations: Philippines ($ph_id), Belgium ($be_id)"
    echo ""
    echo "  Policies:"
    echo "    1. TKT-PH-AVD-Require-MFA           [$POLICY_STATE]"
    echo "    2. TKT-PH-AVD-Location-Restriction   [$POLICY_STATE]"
    echo "    3. TKT-PH-AVD-Block-Legacy-Auth      [enabled]"
    echo ""
    echo "  Group: $SECURITY_GROUP_NAME"
    [[ -n "$bg_user_id" ]] && echo "  Break-glass excluded: $BREAK_GLASS_UPN"
    echo ""
    [[ "$ENFORCE_MODE" == "true" ]] \
        && echo -e "  ${GREEN}Policies are ENFORCED${NC}" \
        || echo -e "  ${YELLOW}REPORT-ONLY — run with --enforce to activate${NC}"
    echo ""
    echo "  Portal: https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies"
    echo "  Log: $LOG_FILE"
    echo ""
}

main "$@"
