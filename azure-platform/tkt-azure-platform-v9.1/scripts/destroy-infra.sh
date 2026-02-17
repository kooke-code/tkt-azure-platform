#!/bin/bash
#===============================================================================
# TKT Azure Platform - V9.1 Infrastructure Destruction Script (Track B)
# Version: 9.1
# Date: 2026-02-17
#
# TRACK B TEARDOWN — Requires Contributor + User Access Administrator
#
# Removes all Azure infrastructure created by deploy-infra.sh:
#   - Deallocate VMs
#   - Delete scaling plan
#   - Remove resource locks
#   - Delete firewall + routes + public IPs (if deployed)
#   - Purge Key Vault
#   - Delete resource group (cascading delete of all resources)
#
# ORDER: Run this script FIRST, then destroy-identity.sh (Track A)
#
# USAGE:
#   bash destroy-infra.sh                       # Interactive
#   bash destroy-infra.sh --force               # Skip confirmation
#   bash destroy-infra.sh --dry-run             # Preview only
#===============================================================================

set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION
#===============================================================================

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-tktph-avd}"
HOSTPOOL_NAME="${HOSTPOOL_NAME:-tktph-hp}"
VNET_NAME="${VNET_NAME:-vnet-tktph-avd-sea}"
SUBNET_NAME="${SUBNET_NAME:-snet-avd}"

DRY_RUN=false
FORCE=false

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
        --dry-run)          DRY_RUN=true; shift ;;
        --force)            FORCE=true; shift ;;
        --resource-group)   RESOURCE_GROUP="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash $0 [OPTIONS]"
            echo ""
            echo "TKT Azure Platform V9.1 - Infrastructure Teardown (Track B)"
            echo ""
            echo "Options:"
            echo "  --dry-run          Preview what would be deleted"
            echo "  --force            Skip confirmation prompts"
            echo "  --resource-group   Resource group name (default: rg-tktph-avd-prod-sea)"
            echo "  --help             Show this help"
            echo ""
            echo "ORDER: Run this script FIRST, then destroy-identity.sh (Track A)."
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

if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    log WARN "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi
log SUCCESS "Prerequisites OK"

#===============================================================================
# INVENTORY
#===============================================================================

echo ""
echo -e "${RED}+===============================================================================+${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}|     TKT Azure Platform V9.1 - INFRASTRUCTURE DESTRUCTION (Track B)            |${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}|  This will PERMANENTLY DELETE all Azure resources in the resource group.       |${NC}"
echo -e "${RED}|  VMs, storage, profiles, shared documents will be destroyed.                   |${NC}"
echo -e "${RED}|                                                                               |${NC}"
echo -e "${RED}+===============================================================================+${NC}"
echo ""

echo -e "  ${BOLD}Resource Group:${NC} $RESOURCE_GROUP"
resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
echo -e "  ${BOLD}Azure Resources:${NC} $resource_count resources will be deleted"
echo ""

echo -e "  ${BOLD}Virtual Machines:${NC}"
az vm list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Size:hardwareProfile.vmSize}" -o table 2>/dev/null || echo "    None found"
echo ""

lock_count=$(az lock list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
if [[ "$lock_count" -gt 0 ]]; then
    echo -e "  ${BOLD}Resource Locks:${NC} $lock_count lock(s) will be removed first"
fi
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}DRY RUN — No changes will be made${NC}"
    echo ""
    exit 0
fi

#===============================================================================
# CONFIRMATION
#===============================================================================

if [[ "$FORCE" != "true" ]]; then
    echo -e "  ${RED}${BOLD}WARNING: This action is IRREVERSIBLE!${NC}"
    echo ""
    echo -e "  Type '${RED}DELETE ${RESOURCE_GROUP}${NC}' to confirm:"
    read -p "  > " confirmation
    if [[ "$confirmation" != "DELETE ${RESOURCE_GROUP}" ]]; then
        log INFO "Destruction cancelled."
        exit 0
    fi
    echo ""
    log WARN "Destruction confirmed. Starting in 5 seconds..."
    sleep 5
fi

#===============================================================================
# STEP 1: REMOVE RESOURCE LOCKS
#===============================================================================

log INFO "Step 1/6: Removing resource locks..."
locks=$(az lock list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$locks" ]]; then
    echo "$locks" | while read -r lock_name; do
        [[ -n "$lock_name" ]] && { log DELETE "Removing lock: $lock_name"; az lock delete --name "$lock_name" --resource-group "$RESOURCE_GROUP" 2>/dev/null || true; }
    done
    log SUCCESS "Resource locks removed"
else
    log INFO "No resource locks found"
fi

#===============================================================================
# STEP 2: DEALLOCATE VMS
#===============================================================================

log INFO "Step 2/6: Deallocating VMs..."
vms=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$vms" ]]; then
    echo "$vms" | while read -r vm_name; do
        [[ -n "$vm_name" ]] && { log DELETE "Deallocating: $vm_name"; az vm deallocate --resource-group "$RESOURCE_GROUP" --name "$vm_name" --no-wait 2>/dev/null || true; }
    done
    log INFO "Waiting for VMs to deallocate (30 seconds)..."
    sleep 30
    log SUCCESS "VMs deallocated"
else
    log INFO "No VMs found"
fi

#===============================================================================
# STEP 3: DELETE SCALING PLAN
#===============================================================================

log INFO "Step 3/6: Deleting scaling plan..."
az desktopvirtualization scaling-plan delete --resource-group "$RESOURCE_GROUP" --name "sp-tktph-avd" --yes 2>/dev/null \
    || log INFO "No scaling plan found"

#===============================================================================
# STEP 4: DELETE AZURE FIREWALL (if deployed)
#===============================================================================

log INFO "Step 4/6: Deleting Azure Firewall resources (if deployed)..."

az network vnet subnet update --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" \
    --remove routeTable 2>/dev/null || true
az network firewall delete --resource-group "$RESOURCE_GROUP" --name "fw-tktph-avd-sea" 2>/dev/null \
    || log INFO "No firewall found"
az network firewall policy delete --resource-group "$RESOURCE_GROUP" --name "fwpol-tktph-avd" 2>/dev/null || true
az network route-table delete --resource-group "$RESOURCE_GROUP" --name "rt-tktph-avd-fw" 2>/dev/null || true
az network public-ip delete --resource-group "$RESOURCE_GROUP" --name "pip-fw-tktph-avd" 2>/dev/null || true
az network public-ip delete --resource-group "$RESOURCE_GROUP" --name "pip-fw-tktph-avd-mgmt" 2>/dev/null || true
log SUCCESS "Azure Firewall resources cleaned up"

#===============================================================================
# STEP 5: DELETE KEY VAULT
#===============================================================================

log INFO "Step 5/6: Deleting Key Vault..."
if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null 2>&1; then
    log DELETE "Deleting Key Vault: $KEY_VAULT_NAME"
    az keyvault delete --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
    az keyvault purge --name "$KEY_VAULT_NAME" 2>/dev/null || true
    log SUCCESS "Key Vault deleted and purged"
else
    log INFO "Key Vault $KEY_VAULT_NAME not found (skipping)"
fi

#===============================================================================
# STEP 6: DELETE RESOURCE GROUP
#===============================================================================

log INFO "Step 6/6: Deleting resource group (this removes all Azure resources)..."
log DELETE "Deleting resource group: $RESOURCE_GROUP"
log WARN "This may take 5-10 minutes..."

az group delete --name "$RESOURCE_GROUP" --yes --no-wait

log SUCCESS "Resource group deletion initiated (running in background)"

#===============================================================================
# SUMMARY
#===============================================================================

echo ""
echo -e "${RED}+===============================================================================+${NC}"
echo -e "${RED}|              INFRASTRUCTURE DESTRUCTION INITIATED (Track B)                    |${NC}"
echo -e "${RED}+===============================================================================+${NC}"
echo ""
echo "  Resource group deletion is running in the background."
echo ""
echo "  Check status:"
echo "    az group show --name $RESOURCE_GROUP 2>&1"
echo ""
echo "  When it returns 'Resource group not found', deletion is complete."
echo ""
echo -e "  ${YELLOW}NEXT STEP (Track A — Global Admin):${NC}"
echo "    bash scripts/destroy-identity.sh"
echo ""
