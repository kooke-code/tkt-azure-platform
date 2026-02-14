#!/bin/bash
#===============================================================================
# TKT Azure Platform - POC Destruction Script
# Version: 8.0
# Date: 2026-02-14
#
# DESCRIPTION:
#   Completely removes all Azure resources created by the deployment script.
#   Use this when the POC is done or you need a clean slate for redeployment.
#
# WHAT GETS DELETED:
#   - All VMs and their disks, NICs, and extensions
#   - AVD host pool, workspace, and application group
#   - Storage account (FSLogix profiles + shared docs)
#   - Log Analytics workspace and data collection rules
#   - NSG, VNet, and all networking
#   - Entra ID users (ph-consultant-001 through 004)
#   - Entra ID security group
#   - Resource lock (if present)
#   - Scaling plan (if present)
#   - Action groups and alerts
#   - The entire resource group
#
# WHAT IS NOT DELETED:
#   - Entra ID roles/permissions (cleaned up with group deletion)
#   - Azure AD app registrations (none created by deploy)
#   - This script and the git repository
#
# USAGE:
#   bash destroy-platform.sh                    # Interactive (asks for confirmation)
#   bash destroy-platform.sh --force            # Skip confirmation (dangerous!)
#   bash destroy-platform.sh --dry-run          # Preview what would be deleted
#   bash destroy-platform.sh --keep-users       # Delete infra but keep Entra users
#
# WARNING: This is IRREVERSIBLE. All data, profiles, and shared documents
#          will be permanently destroyed.
#===============================================================================

set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION (must match deploy script values)
#===============================================================================

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
ENTRA_DOMAIN="${ENTRA_DOMAIN:-tktconsulting.be}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-4}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
HOSTPOOL_NAME="${HOSTPOOL_NAME:-tktph-hp}"

# Script control
DRY_RUN=false
FORCE=false
KEEP_USERS=false

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
        DELETE)  echo -e "${RED}[$timestamp] [DELETE]${NC} $message" ;;
    esac
}

#===============================================================================
# PARSE ARGUMENTS
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)    DRY_RUN=true; shift ;;
            --force)      FORCE=true; shift ;;
            --keep-users) KEEP_USERS=true; shift ;;
            --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
            --domain)     ENTRA_DOMAIN="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: bash $0 [OPTIONS]"
                echo ""
                echo "Destroys all Azure resources created by the TKT AVD platform."
                echo ""
                echo "Options:"
                echo "  --dry-run          Preview what would be deleted"
                echo "  --force            Skip confirmation prompts"
                echo "  --keep-users       Delete infra but keep Entra ID users"
                echo "  --resource-group   Resource group name (default: rg-tktph-avd-prod-sea)"
                echo "  --domain           Entra ID domain (default: tktconsulting.be)"
                echo "  --help             Show this help"
                exit 0
                ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

#===============================================================================
# PREREQUISITES CHECK
#===============================================================================

check_prerequisites() {
    log INFO "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI not found."
        exit 1
    fi

    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Run: az login"
        exit 1
    fi

    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log WARN "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
        exit 0
    fi

    log SUCCESS "Prerequisites OK"
}

#===============================================================================
# INVENTORY
#===============================================================================

show_inventory() {
    echo ""
    echo -e "${RED}===============================================================================${NC}"
    echo -e "${RED}  DESTRUCTION INVENTORY${NC}"
    echo -e "${RED}===============================================================================${NC}"
    echo ""

    # List resource group
    echo -e "  ${BOLD}Resource Group:${NC} $RESOURCE_GROUP"
    echo ""

    # Count resources
    local resource_count
    resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    echo -e "  ${BOLD}Azure Resources:${NC} $resource_count resources will be deleted"

    # List VMs
    echo ""
    echo -e "  ${BOLD}Virtual Machines:${NC}"
    az vm list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Size:hardwareProfile.vmSize}" -o table 2>/dev/null || echo "    None found"

    # List storage
    echo ""
    echo -e "  ${BOLD}Storage Accounts:${NC}"
    az storage account list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Kind:kind}" -o table 2>/dev/null || echo "    None found"

    # List AVD components
    echo ""
    echo -e "  ${BOLD}AVD Components:${NC}"
    az desktopvirtualization hostpool list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null | while read -r hp; do
        echo "    Host Pool: $hp"
    done
    az desktopvirtualization workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null | while read -r ws; do
        echo "    Workspace: $ws"
    done

    # Entra ID users
    if [[ "$KEEP_USERS" == "false" ]]; then
        echo ""
        echo -e "  ${BOLD}Entra ID Users (will be deleted):${NC}"
        for i in $(seq 1 $USER_COUNT); do
            local user_num=$(printf '%03d' $i)
            local upn="${USER_PREFIX}-${user_num}@${ENTRA_DOMAIN}"
            if az ad user show --id "$upn" &>/dev/null 2>&1; then
                echo "    $upn"
            fi
        done
        echo ""
        echo -e "  ${BOLD}Entra ID Group (will be deleted):${NC}"
        echo "    $SECURITY_GROUP_NAME"
    else
        echo ""
        echo -e "  ${BOLD}Entra ID Users:${NC} KEPT (--keep-users flag)"
    fi

    # Check for resource lock
    echo ""
    local lock_count
    lock_count=$(az lock list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$lock_count" -gt 0 ]]; then
        echo -e "  ${BOLD}Resource Locks:${NC} $lock_count lock(s) will be removed first"
        az lock list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Level:level}" -o table 2>/dev/null
    fi

    echo ""
    echo -e "${RED}===============================================================================${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}DRY RUN — No changes will be made${NC}"
        echo ""
        return
    fi
}

#===============================================================================
# CONFIRMATION
#===============================================================================

confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log WARN "Force mode enabled — skipping confirmation"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi

    echo ""
    echo -e "  ${RED}${BOLD}⚠️  WARNING: This action is IRREVERSIBLE!${NC}"
    echo ""
    echo "  All VMs, storage, profiles, shared documents, and configuration"
    echo "  will be permanently destroyed."
    echo ""
    echo -e "  Type '${RED}DELETE ${RESOURCE_GROUP}${NC}' to confirm:"
    echo ""

    read -p "  > " confirmation

    if [[ "$confirmation" != "DELETE ${RESOURCE_GROUP}" ]]; then
        echo ""
        log INFO "Destruction cancelled."
        exit 0
    fi

    echo ""
    log WARN "Destruction confirmed. Starting in 5 seconds..."
    sleep 5
}

#===============================================================================
# STEP 1: REMOVE RESOURCE LOCKS
#===============================================================================

remove_resource_locks() {
    log INFO "Step 1/5: Removing resource locks..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would remove resource locks"
        return
    fi

    local locks
    locks=$(az lock list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")

    if [[ -z "$locks" ]]; then
        log INFO "No resource locks found"
        return
    fi

    echo "$locks" | while read -r lock_name; do
        if [[ -n "$lock_name" ]]; then
            log DELETE "Removing lock: $lock_name"
            az lock delete --name "$lock_name" --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
        fi
    done

    log SUCCESS "Resource locks removed"
}

#===============================================================================
# STEP 2: DEALLOCATE VMS (faster deletion)
#===============================================================================

deallocate_vms() {
    log INFO "Step 2/5: Deallocating VMs (speeds up deletion)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would deallocate VMs"
        return
    fi

    local vms
    vms=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")

    if [[ -z "$vms" ]]; then
        log INFO "No VMs found"
        return
    fi

    echo "$vms" | while read -r vm_name; do
        if [[ -n "$vm_name" ]]; then
            log DELETE "Deallocating: $vm_name"
            az vm deallocate --resource-group "$RESOURCE_GROUP" --name "$vm_name" --no-wait 2>/dev/null || true
        fi
    done

    log INFO "Waiting for VMs to deallocate (30 seconds)..."
    sleep 30
    log SUCCESS "VMs deallocated"
}

#===============================================================================
# STEP 3: DELETE ENTRA ID RESOURCES
#===============================================================================

delete_entra_resources() {
    log INFO "Step 3/5: Deleting Entra ID resources..."

    if [[ "$KEEP_USERS" == "true" ]]; then
        log INFO "Keeping Entra ID users (--keep-users flag)"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Entra ID users and security group"
        return
    fi

    # Delete users
    for i in $(seq 1 $USER_COUNT); do
        local user_num=$(printf '%03d' $i)
        local upn="${USER_PREFIX}-${user_num}@${ENTRA_DOMAIN}"

        if az ad user show --id "$upn" &>/dev/null 2>&1; then
            log DELETE "Deleting user: $upn"
            az ad user delete --id "$upn" 2>/dev/null || log WARN "Could not delete $upn"
        else
            log INFO "User $upn not found (already deleted)"
        fi
    done

    # Delete security group
    local group_id
    group_id=$(az ad group list --display-name "$SECURITY_GROUP_NAME" --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$group_id" ]]; then
        log DELETE "Deleting security group: $SECURITY_GROUP_NAME"
        az ad group delete --group "$group_id" 2>/dev/null || log WARN "Could not delete security group"
    else
        log INFO "Security group not found (already deleted)"
    fi

    # Clean up Entra ID device records
    log INFO "Cleaning up Entra ID device records..."
    local devices
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

    log SUCCESS "Entra ID resources cleaned up"
}

#===============================================================================
# STEP 4: DELETE SCALING PLAN (must be before host pool)
#===============================================================================

delete_scaling_plan() {
    log INFO "Step 4/5: Deleting scaling plan (if exists)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete scaling plan"
        return
    fi

    # Try to delete scaling plan
    az desktopvirtualization scaling-plan delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "sp-tktph-avd" \
        --yes 2>/dev/null || log INFO "No scaling plan found (or already deleted)"

    log SUCCESS "Scaling plan cleanup done"
}

#===============================================================================
# STEP 5: DELETE RESOURCE GROUP (removes everything else)
#===============================================================================

delete_resource_group() {
    log INFO "Step 5/5: Deleting resource group (this removes all Azure resources)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi

    log DELETE "Deleting resource group: $RESOURCE_GROUP"
    log WARN "This may take 5-10 minutes..."

    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait

    log SUCCESS "Resource group deletion initiated (running in background)"
    log INFO "Check status: az group show --name $RESOURCE_GROUP 2>&1"
}

#===============================================================================
# SUMMARY
#===============================================================================

show_destruction_summary() {
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}+===============================================================================+${NC}"
        echo -e "${YELLOW}|                     DRY RUN COMPLETE — NO CHANGES MADE                       |${NC}"
        echo -e "${YELLOW}+===============================================================================+${NC}"
        echo ""
        echo "  Run without --dry-run to actually delete resources."
    else
        echo -e "${RED}+===============================================================================+${NC}"
        echo -e "${RED}|                       DESTRUCTION INITIATED                                   |${NC}"
        echo -e "${RED}+===============================================================================+${NC}"
        echo ""
        echo "  Resource group deletion is running in the background."
        echo ""
        echo "  Check status:"
        echo "    az group show --name $RESOURCE_GROUP 2>&1"
        echo ""
        echo "  When it returns 'Resource group not found', deletion is complete."
        echo ""
        if [[ "$KEEP_USERS" == "true" ]]; then
            echo -e "  ${YELLOW}Note: Entra ID users were kept (--keep-users flag)${NC}"
            echo "  Delete them manually if needed:"
            for i in $(seq 1 $USER_COUNT); do
                local user_num=$(printf '%03d' $i)
                echo "    az ad user delete --id ${USER_PREFIX}-${user_num}@${ENTRA_DOMAIN}"
            done
            echo ""
        fi
        echo "  To redeploy:"
        echo "    cd tkt-azure-platform-v8"
        echo "    bash scripts/deploy-avd-platform.sh"
    fi
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo ""
    echo -e "${RED}+===============================================================================+${NC}"
    echo -e "${RED}|                                                                               |${NC}"
    echo -e "${RED}|         TKT Azure Platform - POC DESTRUCTION SCRIPT                           |${NC}"
    echo -e "${RED}|                                                                               |${NC}"
    echo -e "${RED}|  This will PERMANENTLY DELETE all Azure resources and Entra ID users           |${NC}"
    echo -e "${RED}|  created by the TKT AVD deployment. This action cannot be undone.              |${NC}"
    echo -e "${RED}|                                                                               |${NC}"
    echo -e "${RED}+===============================================================================+${NC}"
    echo ""

    parse_args "$@"
    check_prerequisites
    show_inventory
    confirm_destruction

    remove_resource_locks
    deallocate_vms
    delete_entra_resources
    delete_scaling_plan
    delete_resource_group
    show_destruction_summary
}

main "$@"
