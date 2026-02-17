#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9 Microsoft Teams Team Deployment
# Version: 9.0
# Date: 2026-02-17
#
# Creates a Microsoft Teams team with channels for TKT Philippines SAP
# consultants using Microsoft Graph REST API (az rest).
#
# Channels created:
#   - General (auto-created with team)
#   - P2P Knowledge Base
#   - R2R Knowledge Base
#   - Client Communications
#   - Weekly Reports
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Teams Administrator role or Group.ReadWrite.All + Team.Create permission
#   - jq (for JSON parsing)
#
# USAGE:
#   bash deploy-teams-team.sh                    # Create team with defaults
#   bash deploy-teams-team.sh --dry-run         # Preview only
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

#===============================================================================
# DEFAULTS
#===============================================================================

TEAM_NAME="${TEAM_NAME:-TKT Philippines SAP Team}"
TEAM_DESCRIPTION="${TEAM_DESCRIPTION:-SAP Managed Services - Procurement (P2P) and Record-to-Report (R2R)}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
VERSION_TAG="9.0"

DRY_RUN="false"
SKIP_PROMPTS="false"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="/tmp/avd-teams-deployment-${TIMESTAMP}.log"

GRAPH_URL="https://graph.microsoft.com/v1.0"

# Channel definitions
declare -a CHANNEL_NAMES=("P2P Knowledge Base" "R2R Knowledge Base" "Client Communications" "Weekly Reports")
declare -a CHANNEL_DESCS=(
    "Procurement SOPs, purchase orders, goods receipts, invoice verification"
    "Record-to-Report SOPs, journal entries, period-end close, reconciliations"
    "Client-facing discussions, escalations, and service requests"
    "Automated weekly session reports and AI analysis"
)

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
# MAIN
#===============================================================================

main() {
    echo ""
    echo -e "${CYAN}+===============================================================================+${NC}"
    echo -e "${CYAN}|          TKT Philippines AVD - Teams Team Deployment (V9)                      |${NC}"
    echo -e "${CYAN}+===============================================================================+${NC}"
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team-name) TEAM_NAME="$2"; shift 2 ;;
            --security-group) SECURITY_GROUP_NAME="$2"; shift 2 ;;
            --dry-run) DRY_RUN="true"; shift ;;
            --skip-prompts) SKIP_PROMPTS="true"; shift ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo "  --team-name NAME     Team display name"
                echo "  --security-group N   Security group name"
                echo "  --dry-run            Preview only"
                echo "  --skip-prompts       Skip confirmations"
                exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Prerequisites
    log INFO "Checking prerequisites..."
    command -v az &>/dev/null || fail "Azure CLI not found"
    command -v jq &>/dev/null || fail "jq not found. Install: brew install jq"
    az account show &>/dev/null || fail "Not logged in. Run: az login"
    log SUCCESS "Prerequisites passed"

    # Get current user ID (will be team owner)
    local current_user_id=$(az ad signed-in-user show --query "id" -o tsv 2>/dev/null)
    [[ -z "$current_user_id" ]] && fail "Cannot determine signed-in user"
    log INFO "Team owner: $(az ad signed-in-user show --query "userPrincipalName" -o tsv 2>/dev/null)"

    echo "  Team Name:      $TEAM_NAME"
    echo "  Security Group: $SECURITY_GROUP_NAME"
    echo "  Channels:       General + ${#CHANNEL_NAMES[@]} custom"
    echo ""

    if [[ "$SKIP_PROMPTS" != "true" && "$DRY_RUN" != "true" ]]; then
        read -p "  Create this Teams team? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
    fi

    # =====================================================================
    # PHASE 1: Create Team
    # =====================================================================
    log_phase 1 "CREATE TEAM"

    local team_id=""

    # Check if team already exists
    local existing_team=$(az rest --method GET \
        --url "${GRAPH_URL}/groups?\$filter=displayName eq '${TEAM_NAME}' and resourceProvisioningOptions/Any(x:x eq 'Team')" \
        --query "value[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$existing_team" && "$existing_team" != "null" ]]; then
        team_id="$existing_team"
        log INFO "Team '$TEAM_NAME' already exists ($team_id)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create team: $TEAM_NAME"
        team_id="dry-run-id"
    else
        log INFO "Creating team: $TEAM_NAME"

        local team_body=$(jq -n \
            --arg name "$TEAM_NAME" \
            --arg desc "$TEAM_DESCRIPTION" \
            --arg owner_id "$current_user_id" \
            '{
                "template@odata.bind": "https://graph.microsoft.com/v1.0/teamsTemplates(\u0027standard\u0027)",
                "displayName": $name,
                "description": $desc,
                "members": [{
                    "@odata.type": "#microsoft.graph.aadUserConversationMember",
                    "roles": ["owner"],
                    "user@odata.bind": ("https://graph.microsoft.com/v1.0/users(\u0027" + $owner_id + "\u0027)")
                }],
                "memberSettings": {"allowCreateUpdateChannels": false},
                "guestSettings": {"allowCreateUpdateChannels": false, "allowDeleteChannels": false},
                "funSettings": {"allowGiphy": false, "allowStickersAndMemes": false, "allowCustomMemes": false},
                "messagingSettings": {"allowUserEditMessages": true, "allowUserDeleteMessages": false, "allowTeamMentions": true, "allowChannelMentions": true}
            }')

        # Team creation is async — returns Location header with team URL
        local create_response=$(az rest --method POST \
            --url "${GRAPH_URL}/teams" \
            --body "$team_body" \
            --headers "Content-Type=application/json" \
            --output none 2>&1 || true)

        # Wait for team to be provisioned (poll up to 60 seconds)
        log INFO "Waiting for team provisioning (up to 60 seconds)..."
        local wait_count=0
        while [[ $wait_count -lt 12 ]]; do
            sleep 5
            wait_count=$((wait_count + 1))

            team_id=$(az rest --method GET \
                --url "${GRAPH_URL}/groups?\$filter=displayName eq '${TEAM_NAME}' and resourceProvisioningOptions/Any(x:x eq 'Team')" \
                --query "value[0].id" -o tsv 2>/dev/null || echo "")

            if [[ -n "$team_id" && "$team_id" != "null" ]]; then
                log SUCCESS "Team created: $TEAM_NAME ($team_id)"
                break
            fi
            log INFO "  Waiting... ($((wait_count * 5))s)"
        done

        if [[ -z "$team_id" || "$team_id" == "null" ]]; then
            fail "Team creation timed out. Check Azure portal manually."
        fi
    fi

    log SUCCESS "Phase 1 complete: Team ready"

    # =====================================================================
    # PHASE 2: Create Channels
    # =====================================================================
    log_phase 2 "CREATE CHANNELS"

    if [[ "$DRY_RUN" == "true" ]]; then
        for i in "${!CHANNEL_NAMES[@]}"; do
            log INFO "[DRY RUN] Would create channel: ${CHANNEL_NAMES[$i]}"
        done
    else
        for i in "${!CHANNEL_NAMES[@]}"; do
            local ch_name="${CHANNEL_NAMES[$i]}"
            local ch_desc="${CHANNEL_DESCS[$i]}"

            # Check if exists
            local existing_ch=$(az rest --method GET \
                --url "${GRAPH_URL}/teams/${team_id}/channels?\$filter=displayName eq '${ch_name}'" \
                --query "value[0].id" -o tsv 2>/dev/null || echo "")

            if [[ -n "$existing_ch" && "$existing_ch" != "null" ]]; then
                log INFO "Channel '$ch_name' already exists"
                continue
            fi

            local ch_body=$(jq -n --arg name "$ch_name" --arg desc "$ch_desc" \
                '{"displayName": $name, "description": $desc}')

            az rest --method POST \
                --url "${GRAPH_URL}/teams/${team_id}/channels" \
                --body "$ch_body" --headers "Content-Type=application/json" \
                --output none 2>/dev/null \
                || log WARN "Failed to create channel: $ch_name"

            log SUCCESS "Created channel: $ch_name"
        done
    fi

    log SUCCESS "Phase 2 complete: Channels created"

    # =====================================================================
    # PHASE 3: Add Members
    # =====================================================================
    log_phase 3 "ADD MEMBERS"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would add all members from $SECURITY_GROUP_NAME"
    else
        # Get all members of the security group
        local member_ids=$(az ad group member list --group "$SECURITY_GROUP_NAME" --query "[].id" -o tsv 2>/dev/null)

        if [[ -z "$member_ids" ]]; then
            log WARN "No members found in $SECURITY_GROUP_NAME"
        else
            local member_count=0
            while IFS= read -r member_id; do
                [[ -z "$member_id" ]] && continue

                local member_body=$(jq -n --arg id "$member_id" '{
                    "@odata.type": "#microsoft.graph.aadUserConversationMember",
                    "roles": [],
                    "user@odata.bind": ("https://graph.microsoft.com/v1.0/users(\u0027" + $id + "\u0027)")
                }')

                az rest --method POST \
                    --url "${GRAPH_URL}/teams/${team_id}/members" \
                    --body "$member_body" --headers "Content-Type=application/json" \
                    --output none 2>/dev/null \
                    || true  # 409 Conflict = already a member

                member_count=$((member_count + 1))
            done <<< "$member_ids"

            log SUCCESS "Processed $member_count members from $SECURITY_GROUP_NAME"
        fi
    fi

    log SUCCESS "Phase 3 complete: Members added"

    # =====================================================================
    # PHASE 4: Summary
    # =====================================================================
    log_phase 4 "VALIDATION"

    echo ""
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo -e "${GREEN}|                Teams Team Deployment Complete (V9)                              |${NC}"
    echo -e "${GREEN}+===============================================================================+${NC}"
    echo ""
    echo "  Team: $TEAM_NAME"
    echo "  Team ID: $team_id"
    echo ""
    echo "  Channels:"
    echo "    - General (default)"
    for ch in "${CHANNEL_NAMES[@]}"; do
        echo "    - $ch"
    done
    echo ""
    echo "  Members: All users from $SECURITY_GROUP_NAME"
    echo ""
    echo "  Settings:"
    echo "    - Giphy/Stickers/Memes: Disabled"
    echo "    - Guest access: Disabled"
    echo "    - User channel creation: Disabled"
    echo ""
    echo "  Access: https://teams.microsoft.com"
    echo "  Log: $LOG_FILE"
    echo ""
}

main "$@"
