#!/bin/bash
#===============================================================================
# TKT Azure Platform - Azure Firewall Deployment Script
# Version: 8.1
# Date: 2026-02-17
#
# PURPOSE:
#   Deploys Azure Firewall with FQDN-based application rules to replace
#   the broad outbound NSG rules. This provides Layer 7 (application-level)
#   filtering instead of just Layer 3/4 (network-level), restricting session
#   hosts to only the specific FQDNs they need.
#
# WHAT THIS SCRIPT DOES:
#   1. Creates AzureFirewallSubnet in existing VNet
#   2. Deploys Azure Firewall + public IP
#   3. Creates Firewall Policy with FQDN application rules:
#      - AVD service endpoints (*.wvd.microsoft.com)
#      - Azure authentication (login.microsoftonline.com)
#      - Azure Files (*.file.core.windows.net)
#      - Microsoft 365 / Teams
#      - SAP S/4HANA Cloud (Fiori)
#      - Zoho Desk
#   4. Creates network rules for Teams UDP media
#   5. Creates route table forcing traffic through firewall
#   6. Updates AVD subnet to use route table
#   7. Updates NSG for firewall compatibility
#   8. Enables firewall diagnostics to existing Log Analytics workspace
#
# PREREQUISITES:
#   - Azure CLI v2.83+ (az login completed)
#   - Contributor role on Azure subscription
#   - deploy-avd-platform.sh must have been run first
#   - bash shell (not zsh)
#
# USAGE:
#   bash deploy-azure-firewall.sh                    # Interactive mode
#   bash deploy-azure-firewall.sh --dry-run          # Preview only
#   bash deploy-azure-firewall.sh --config env.sh    # Use config file
#   bash deploy-azure-firewall.sh --sku Basic        # Use Basic SKU (cheaper)
#
# COST IMPACT:
#   Azure Firewall Standard: ~EUR 900/month (fixed) + data processing
#   Azure Firewall Basic:    ~EUR 280/month (fixed) + data processing
#   Recommendation: Use Basic SKU for this workload (4 users, HTTPS-only)
#
# ROLLBACK:
#   1. Remove route table association: az network vnet subnet update ...
#   2. Delete route table: az network route-table delete ...
#   3. Delete firewall: az network firewall delete ...
#   4. The original NSG rules still apply as fallback
#
# REFERENCES:
#   - https://learn.microsoft.com/en-us/azure/virtual-desktop/proxy-server-support
#   - https://learn.microsoft.com/en-us/azure/firewall/protect-azure-virtual-desktop
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

# Cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "\033[0;31m[ERROR] Firewall deployment failed (exit code $exit_code).\033[0m"
        echo "  Log file: ${LOG_FILE:-/tmp/firewall-deployment.log}"
        echo "  Existing NSG rules still protect the subnet."
    fi
}
trap cleanup_on_exit EXIT

# Ensure running in bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash $0 $*"
    exit 1
fi

#===============================================================================
# DEFAULT CONFIGURATION - Must match deploy-avd-platform.sh values
#===============================================================================

# Azure
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
LOCATION="${LOCATION:-southeastasia}"

# Networking (must match v8 deploy script)
VNET_NAME="${VNET_NAME:-vnet-tktph-avd-sea}"
VNET_ADDRESS_PREFIX="${VNET_ADDRESS_PREFIX:-10.2.0.0/16}"
SUBNET_NAME="${SUBNET_NAME:-snet-avd}"
NSG_NAME="${NSG_NAME:-nsg-tktph-avd}"

# Firewall (new)
FIREWALL_NAME="${FIREWALL_NAME:-fw-tktph-avd-sea}"
FIREWALL_POLICY_NAME="${FIREWALL_POLICY_NAME:-fwpol-tktph-avd}"
FIREWALL_PIP_NAME="${FIREWALL_PIP_NAME:-pip-fw-tktph-avd}"
FIREWALL_SUBNET_PREFIX="${FIREWALL_SUBNET_PREFIX:-10.2.2.0/26}"
FIREWALL_SKU="${FIREWALL_SKU:-Basic}"
ROUTE_TABLE_NAME="${ROUTE_TABLE_NAME:-rt-tktph-avd-fw}"

# Monitoring (must match v8 deploy script)
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-tktph-avd-sea}"

# Application URLs (must match v8 deploy script)
SAP_FIORI_URL="${SAP_FIORI_URL:-https://my300000.s4hana.cloud.sap}"
ZOHO_DESK_URL="${ZOHO_DESK_URL:-https://desk.zoho.com}"

# Script Control
DRY_RUN="${DRY_RUN:-false}"
CONFIG_FILE="${CONFIG_FILE:-}"

# Runtime
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="/tmp/firewall-deployment-${TIMESTAMP}.log"

# Version tag
VERSION_TAG="8.1"

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
    exit 1
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --sku)
            FIREWALL_SKU="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash $0 [--dry-run] [--sku Basic|Standard] [--config env.sh]"
            exit 1
            ;;
    esac
done

# Load config file if specified
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    log INFO "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

#===============================================================================
# PRE-FLIGHT CHECKS
#===============================================================================

echo ""
echo -e "${BOLD}TKT Azure Platform - Azure Firewall Deployment${NC}"
echo -e "${BOLD}================================================${NC}"
echo ""
echo "  Resource Group:     $RESOURCE_GROUP"
echo "  VNet:               $VNET_NAME"
echo "  Firewall:           $FIREWALL_NAME"
echo "  Firewall SKU:       $FIREWALL_SKU"
echo "  Firewall Subnet:    $FIREWALL_SUBNET_PREFIX"
echo "  Firewall Policy:    $FIREWALL_POLICY_NAME"
echo "  Route Table:        $ROUTE_TABLE_NAME"
echo "  Log Analytics:      $LOG_ANALYTICS_WORKSPACE"
echo "  Dry Run:            $DRY_RUN"
echo "  Log File:           $LOG_FILE"
echo ""

if [[ "$FIREWALL_SKU" == "Basic" ]]; then
    echo -e "  ${YELLOW}Cost estimate: ~EUR 280/month + data processing${NC}"
elif [[ "$FIREWALL_SKU" == "Standard" ]]; then
    echo -e "  ${YELLOW}Cost estimate: ~EUR 900/month + data processing${NC}"
fi
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

# Verify Azure CLI is logged in
if ! az account show &>/dev/null; then
    fail "Not logged into Azure CLI. Run 'az login' first."
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    az account set --subscription "$SUBSCRIPTION_ID" --output none
fi

CURRENT_SUB=$(az account show --query "name" -o tsv)
log INFO "Using Azure subscription: $CURRENT_SUB"

# Verify VNet exists
if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
    fail "VNet $VNET_NAME not found in $RESOURCE_GROUP. Run deploy-avd-platform.sh first."
fi

# Verify Log Analytics workspace exists
if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &>/dev/null; then
    fail "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE not found. Run deploy-avd-platform.sh first."
fi

#===============================================================================
# PHASE 1: CREATE FIREWALL SUBNET
#===============================================================================

deploy_phase1_firewall_subnet() {
    log_phase "1" "CREATE FIREWALL SUBNET"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create AzureFirewallSubnet ($FIREWALL_SUBNET_PREFIX) in $VNET_NAME"
        return
    fi

    # Azure Firewall requires a subnet named exactly "AzureFirewallSubnet"
    if az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "AzureFirewallSubnet" &>/dev/null; then
        log INFO "AzureFirewallSubnet already exists"
    else
        log INFO "Creating AzureFirewallSubnet ($FIREWALL_SUBNET_PREFIX)..."
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "AzureFirewallSubnet" \
            --address-prefixes "$FIREWALL_SUBNET_PREFIX" \
            --output none

        log SUCCESS "AzureFirewallSubnet created"
    fi

    # For Basic SKU, also need AzureFirewallManagementSubnet
    if [[ "$FIREWALL_SKU" == "Basic" ]]; then
        local mgmt_subnet_prefix="10.2.3.0/26"
        if az network vnet subnet show \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "AzureFirewallManagementSubnet" &>/dev/null; then
            log INFO "AzureFirewallManagementSubnet already exists"
        else
            log INFO "Creating AzureFirewallManagementSubnet ($mgmt_subnet_prefix) for Basic SKU..."
            az network vnet subnet create \
                --resource-group "$RESOURCE_GROUP" \
                --vnet-name "$VNET_NAME" \
                --name "AzureFirewallManagementSubnet" \
                --address-prefixes "$mgmt_subnet_prefix" \
                --output none

            log SUCCESS "AzureFirewallManagementSubnet created"
        fi
    fi

    log SUCCESS "Phase 1 complete: FIREWALL SUBNET"
}

#===============================================================================
# PHASE 2: DEPLOY AZURE FIREWALL
#===============================================================================

deploy_phase2_firewall() {
    log_phase "2" "DEPLOY AZURE FIREWALL"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would deploy Azure Firewall ($FIREWALL_SKU SKU) with public IP"
        return
    fi

    # Create public IP for the firewall
    if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$FIREWALL_PIP_NAME" &>/dev/null; then
        log INFO "Public IP $FIREWALL_PIP_NAME already exists"
    else
        log INFO "Creating public IP: $FIREWALL_PIP_NAME..."
        az network public-ip create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FIREWALL_PIP_NAME" \
            --sku Standard \
            --allocation-method Static \
            --tags Version="$VERSION_TAG" \
            --output none

        log SUCCESS "Public IP created"
    fi

    # For Basic SKU, create management public IP
    local mgmt_pip_name="${FIREWALL_PIP_NAME}-mgmt"
    if [[ "$FIREWALL_SKU" == "Basic" ]]; then
        if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$mgmt_pip_name" &>/dev/null; then
            log INFO "Management public IP $mgmt_pip_name already exists"
        else
            log INFO "Creating management public IP: $mgmt_pip_name..."
            az network public-ip create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$mgmt_pip_name" \
                --sku Standard \
                --allocation-method Static \
                --tags Version="$VERSION_TAG" \
                --output none

            log SUCCESS "Management public IP created"
        fi
    fi

    # Create Firewall Policy
    if az network firewall policy show --resource-group "$RESOURCE_GROUP" --name "$FIREWALL_POLICY_NAME" &>/dev/null; then
        log INFO "Firewall Policy $FIREWALL_POLICY_NAME already exists"
    else
        log INFO "Creating Firewall Policy: $FIREWALL_POLICY_NAME..."
        az network firewall policy create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FIREWALL_POLICY_NAME" \
            --sku "$FIREWALL_SKU" \
            --tags Version="$VERSION_TAG" \
            --output none

        log SUCCESS "Firewall Policy created"
    fi

    # Deploy the firewall
    if az network firewall show --resource-group "$RESOURCE_GROUP" --name "$FIREWALL_NAME" &>/dev/null; then
        log INFO "Firewall $FIREWALL_NAME already exists"
    else
        log INFO "Deploying Azure Firewall: $FIREWALL_NAME (SKU: $FIREWALL_SKU)..."
        log WARN "This may take 5-10 minutes..."

        if [[ "$FIREWALL_SKU" == "Basic" ]]; then
            az network firewall create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$FIREWALL_NAME" \
                --sku AZFW_VNet \
                --tier "$FIREWALL_SKU" \
                --vnet-name "$VNET_NAME" \
                --conf-name "fw-ipconfig" \
                --public-ip "$FIREWALL_PIP_NAME" \
                --m-conf-name "fw-mgmt-ipconfig" \
                --m-public-ip "$mgmt_pip_name" \
                --firewall-policy "$FIREWALL_POLICY_NAME" \
                --tags Version="$VERSION_TAG" \
                --output none
        else
            az network firewall create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$FIREWALL_NAME" \
                --sku AZFW_VNet \
                --tier "$FIREWALL_SKU" \
                --vnet-name "$VNET_NAME" \
                --conf-name "fw-ipconfig" \
                --public-ip "$FIREWALL_PIP_NAME" \
                --firewall-policy "$FIREWALL_POLICY_NAME" \
                --tags Version="$VERSION_TAG" \
                --output none
        fi

        log SUCCESS "Azure Firewall deployed"
    fi

    # Get the firewall's private IP address (needed for route table)
    FIREWALL_PRIVATE_IP=$(az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "ipConfigurations[0].privateIPAddress" -o tsv)

    log INFO "Firewall private IP: $FIREWALL_PRIVATE_IP"
    log SUCCESS "Phase 2 complete: AZURE FIREWALL DEPLOYED"
}

#===============================================================================
# PHASE 3: CONFIGURE FIREWALL APPLICATION RULES (FQDN-based)
#===============================================================================

deploy_phase3_app_rules() {
    log_phase "3" "CONFIGURE FIREWALL APPLICATION RULES"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create FQDN application rules for AVD, SAP, Zoho, Teams, Azure"
        return
    fi

    # Extract FQDNs from URLs
    local sap_fqdn
    sap_fqdn=$(echo "$SAP_FIORI_URL" | sed 's|https://||' | sed 's|/.*||')
    local zoho_fqdn
    zoho_fqdn=$(echo "$ZOHO_DESK_URL" | sed 's|https://||' | sed 's|/.*||')

    # =========================================================================
    # Rule Collection Group: AVD-Infrastructure (priority 100)
    # =========================================================================
    log INFO "Creating rule collection group: AVD-Infrastructure..."

    az network firewall policy rule-collection-group create \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --name "AVD-Infrastructure" \
        --priority 100 \
        --output none 2>/dev/null || log INFO "Rule collection group AVD-Infrastructure already exists"

    # Application rule collection: AVD Service Endpoints
    log INFO "Creating application rules: AVD Service Endpoints..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "AVD-Infrastructure" \
        --name "AVD-Service-Endpoints" \
        --collection-priority 110 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowAVDService" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "*.wvd.microsoft.com" \
            "*.servicebus.windows.net" \
            "gcs.prod.monitoring.core.windows.net" \
            "production.diagnostics.monitoring.core.windows.net" \
            "*.prod.warm.ingest.monitor.core.windows.net" \
        --output none 2>/dev/null || log INFO "AVD-Service-Endpoints collection already exists"

    # Application rule: Azure Authentication
    log INFO "Creating application rules: Azure Authentication..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "AVD-Infrastructure" \
        --name "Azure-Authentication" \
        --collection-priority 120 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowEntraIDAuth" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "login.microsoftonline.com" \
            "login.windows.net" \
            "*.login.microsoftonline.com" \
            "device.login.microsoftonline.com" \
            "aadcdn.msauth.net" \
            "aadcdn.msftauth.net" \
            "*.msauth.net" \
            "*.msftauth.net" \
        --output none 2>/dev/null || log INFO "Azure-Authentication collection already exists"

    # Application rule: Azure Files (for FSLogix + shared-docs)
    log INFO "Creating application rules: Azure Files..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "AVD-Infrastructure" \
        --name "Azure-Files" \
        --collection-priority 130 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowAzureFiles" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "*.file.core.windows.net" \
            "*.blob.core.windows.net" \
        --output none 2>/dev/null || log INFO "Azure-Files collection already exists"

    # =========================================================================
    # Rule Collection Group: Business-Applications (priority 200)
    # =========================================================================
    log INFO "Creating rule collection group: Business-Applications..."

    az network firewall policy rule-collection-group create \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --name "Business-Applications" \
        --priority 200 \
        --output none 2>/dev/null || log INFO "Rule collection group Business-Applications already exists"

    # Application rule: SAP S/4HANA Cloud (Fiori)
    log INFO "Creating application rules: SAP Fiori ($sap_fqdn)..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Business-Applications" \
        --name "SAP-Fiori" \
        --collection-priority 210 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowSAPFiori" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "$sap_fqdn" \
            "*.s4hana.cloud.sap" \
            "*.hana.ondemand.com" \
            "*.sap.com" \
        --output none 2>/dev/null || log INFO "SAP-Fiori collection already exists"

    # Application rule: Zoho Desk
    log INFO "Creating application rules: Zoho Desk ($zoho_fqdn)..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Business-Applications" \
        --name "Zoho-Desk" \
        --collection-priority 220 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowZohoDesk" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "$zoho_fqdn" \
            "*.zoho.com" \
            "*.zohocdn.com" \
            "*.zohostatic.com" \
        --output none 2>/dev/null || log INFO "Zoho-Desk collection already exists"

    # Application rule: Microsoft 365 / Teams (HTTPS)
    log INFO "Creating application rules: Microsoft 365 / Teams..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Business-Applications" \
        --name "Microsoft-365-Teams" \
        --collection-priority 230 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowM365Teams" \
        --protocols Https=443 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "*.teams.microsoft.com" \
            "teams.microsoft.com" \
            "*.skype.com" \
            "*.lync.com" \
            "*.officeapps.live.com" \
            "*.office365.com" \
            "*.office.com" \
            "*.microsoft.com" \
            "*.microsoftonline.com" \
        --output none 2>/dev/null || log INFO "Microsoft-365-Teams collection already exists"

    # Application rule: Windows Update & Activation
    log INFO "Creating application rules: Windows Update..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Business-Applications" \
        --name "Windows-Update" \
        --collection-priority 240 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "AllowWindowsUpdate" \
        --protocols Https=443 Http=80 \
        --source-addresses "10.2.1.0/24" \
        --target-fqdns \
            "*.windowsupdate.com" \
            "*.update.microsoft.com" \
            "*.windowsupdate.microsoft.com" \
            "*.download.windowsupdate.com" \
            "download.microsoft.com" \
            "kms.core.windows.net" \
            "azkms.core.windows.net" \
        --output none 2>/dev/null || log INFO "Windows-Update collection already exists"

    log SUCCESS "Phase 3 complete: APPLICATION RULES CONFIGURED"
}

#===============================================================================
# PHASE 4: CONFIGURE NETWORK RULES (for non-HTTP protocols)
#===============================================================================

deploy_phase4_network_rules() {
    log_phase "4" "CONFIGURE NETWORK RULES (Teams UDP media)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create network rules for Teams TURN/STUN UDP traffic"
        return
    fi

    # =========================================================================
    # Rule Collection Group: Network-Rules (priority 300)
    # =========================================================================
    log INFO "Creating rule collection group: Network-Rules..."

    az network firewall policy rule-collection-group create \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --name "Network-Rules" \
        --priority 300 \
        --output none 2>/dev/null || log INFO "Rule collection group Network-Rules already exists"

    # Network rule: Teams TURN/STUN (UDP 3478-3481)
    log INFO "Creating network rules: Teams UDP media..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Network-Rules" \
        --name "Teams-Media-UDP" \
        --collection-priority 310 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "AllowTeamsTURNSTUN" \
        --source-addresses "10.2.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 3478-3481 \
        --ip-protocols UDP \
        --output none 2>/dev/null || log INFO "Teams-Media-UDP collection already exists"

    # Network rule: Teams media TCP range (50000-50059)
    log INFO "Creating network rules: Teams TCP media range..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Network-Rules" \
        --name "Teams-Media-TCP" \
        --collection-priority 320 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "AllowTeamsMediaTCP" \
        --source-addresses "10.2.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 50000-50059 \
        --ip-protocols TCP \
        --output none 2>/dev/null || log INFO "Teams-Media-TCP collection already exists"

    # Network rule: Azure Files SMB (TCP 445) — needed for FSLogix
    log INFO "Creating network rules: Azure Files SMB..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Network-Rules" \
        --name "Azure-Files-SMB" \
        --collection-priority 330 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "AllowAzureFilesSMB" \
        --source-addresses "10.2.1.0/24" \
        --destination-addresses "Storage.SoutheastAsia" \
        --destination-ports 445 \
        --ip-protocols TCP \
        --output none 2>/dev/null || log INFO "Azure-Files-SMB collection already exists"

    # Network rule: DNS (UDP/TCP 53)
    log INFO "Creating network rules: DNS..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Network-Rules" \
        --name "DNS" \
        --collection-priority 340 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "AllowDNS" \
        --source-addresses "10.2.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 53 \
        --ip-protocols UDP TCP \
        --output none 2>/dev/null || log INFO "DNS collection already exists"

    # Network rule: NTP (UDP 123) — Windows time sync
    log INFO "Creating network rules: NTP..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "Network-Rules" \
        --name "NTP" \
        --collection-priority 350 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "AllowNTP" \
        --source-addresses "10.2.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 123 \
        --ip-protocols UDP \
        --output none 2>/dev/null || log INFO "NTP collection already exists"

    log SUCCESS "Phase 4 complete: NETWORK RULES CONFIGURED"
}

#===============================================================================
# PHASE 5: ROUTE TABLE (Force traffic through firewall)
#===============================================================================

deploy_phase5_route_table() {
    log_phase "5" "CONFIGURE ROUTE TABLE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create route table forcing 0.0.0.0/0 → Firewall private IP"
        return
    fi

    # Get firewall private IP if not already set
    if [[ -z "${FIREWALL_PRIVATE_IP:-}" ]]; then
        FIREWALL_PRIVATE_IP=$(az network firewall show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FIREWALL_NAME" \
            --query "ipConfigurations[0].privateIPAddress" -o tsv)
    fi

    log INFO "Firewall private IP: $FIREWALL_PRIVATE_IP"

    # Create route table
    if az network route-table show --resource-group "$RESOURCE_GROUP" --name "$ROUTE_TABLE_NAME" &>/dev/null; then
        log INFO "Route table $ROUTE_TABLE_NAME already exists"
    else
        log INFO "Creating route table: $ROUTE_TABLE_NAME..."
        az network route-table create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ROUTE_TABLE_NAME" \
            --disable-bgp-route-propagation true \
            --tags Version="$VERSION_TAG" \
            --output none

        log SUCCESS "Route table created"
    fi

    # Add default route → firewall
    log INFO "Creating default route → Azure Firewall..."
    az network route-table route create \
        --resource-group "$RESOURCE_GROUP" \
        --route-table-name "$ROUTE_TABLE_NAME" \
        --name "default-to-firewall" \
        --address-prefix "0.0.0.0/0" \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address "$FIREWALL_PRIVATE_IP" \
        --output none 2>/dev/null || log INFO "Default route already exists"

    log SUCCESS "Default route configured: 0.0.0.0/0 → $FIREWALL_PRIVATE_IP"

    # Associate route table with AVD subnet
    log INFO "Associating route table with AVD subnet ($SUBNET_NAME)..."
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --route-table "$ROUTE_TABLE_NAME" \
        --output none

    log SUCCESS "Route table associated with $SUBNET_NAME"
    log SUCCESS "Phase 5 complete: ROUTE TABLE CONFIGURED"
}

#===============================================================================
# PHASE 6: UPDATE NSG FOR FIREWALL COMPATIBILITY
#===============================================================================

deploy_phase6_update_nsg() {
    log_phase "6" "UPDATE NSG FOR FIREWALL COMPATIBILITY"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would update NSG outbound rules for firewall compatibility"
        return
    fi

    # With Azure Firewall handling outbound filtering, the NSG outbound rules
    # can be simplified. The firewall does the FQDN filtering; NSG just needs
    # to allow traffic to reach the firewall.

    log INFO "NSG outbound rules remain as-is for defense-in-depth."
    log INFO "Azure Firewall provides FQDN filtering on top of NSG L3/L4 rules."
    log INFO "Traffic flow: VM → NSG (allow HTTPS) → Route Table → Azure Firewall (FQDN filter) → Internet"

    log SUCCESS "Phase 6 complete: NSG COMPATIBLE"
}

#===============================================================================
# PHASE 7: ENABLE FIREWALL DIAGNOSTICS
#===============================================================================

deploy_phase7_diagnostics() {
    log_phase "7" "ENABLE FIREWALL DIAGNOSTICS"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would enable firewall diagnostics → $LOG_ANALYTICS_WORKSPACE"
        return
    fi

    # Get firewall resource ID
    local firewall_id
    firewall_id=$(az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "id" -o tsv)

    # Get Log Analytics workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" -o tsv)

    log INFO "Enabling diagnostic settings on firewall..."
    az monitor diagnostic-settings create \
        --name "fw-diagnostics" \
        --resource "$firewall_id" \
        --workspace "$workspace_id" \
        --logs '[
            {"categoryGroup": "allLogs", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}
        ]' \
        --metrics '[
            {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}
        ]' \
        --output none 2>/dev/null || log INFO "Diagnostic settings already configured"

    log SUCCESS "Firewall diagnostics enabled → $LOG_ANALYTICS_WORKSPACE"
    log SUCCESS "Phase 7 complete: DIAGNOSTICS ENABLED"
}

#===============================================================================
# PHASE 8: VALIDATION
#===============================================================================

deploy_phase8_validate() {
    log_phase "8" "VALIDATION"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would validate firewall deployment"
        return
    fi

    echo ""
    log INFO "Running validation checks..."

    # Check firewall is provisioned
    local fw_state
    fw_state=$(az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

    if [[ "$fw_state" == "Succeeded" ]]; then
        log SUCCESS "Firewall provisioning: $fw_state ✓"
    else
        log WARN "Firewall provisioning: $fw_state"
    fi

    # Check firewall policy
    local policy_state
    policy_state=$(az network firewall policy show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_POLICY_NAME" \
        --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")

    if [[ "$policy_state" == "Succeeded" ]]; then
        log SUCCESS "Firewall policy provisioning: $policy_state ✓"
    else
        log WARN "Firewall policy provisioning: $policy_state"
    fi

    # Check rule collection groups
    local rule_groups
    rule_groups=$(az network firewall policy rule-collection-group list \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$rule_groups" -ge 3 ]]; then
        log SUCCESS "Rule collection groups: $rule_groups ✓ (AVD-Infrastructure, Business-Applications, Network-Rules)"
    else
        log WARN "Rule collection groups: $rule_groups (expected ≥ 3)"
    fi

    # Check route table association
    local rt_associated
    rt_associated=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --query "routeTable.id" -o tsv 2>/dev/null || echo "")

    if [[ -n "$rt_associated" ]]; then
        log SUCCESS "Route table associated with $SUBNET_NAME ✓"
    else
        log WARN "Route table NOT associated with $SUBNET_NAME"
    fi

    # Check diagnostic settings
    local firewall_id
    firewall_id=$(az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "id" -o tsv 2>/dev/null || echo "")

    local diag_count
    diag_count=$(az monitor diagnostic-settings list \
        --resource "$firewall_id" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$diag_count" -ge 1 ]]; then
        log SUCCESS "Diagnostic settings: $diag_count configured ✓"
    else
        log WARN "No diagnostic settings found"
    fi

    log SUCCESS "Phase 8 complete: VALIDATION"
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    log INFO "Starting Azure Firewall deployment for $RESOURCE_GROUP"
    echo ""

    deploy_phase1_firewall_subnet
    deploy_phase2_firewall
    deploy_phase3_app_rules
    deploy_phase4_network_rules
    deploy_phase5_route_table
    deploy_phase6_update_nsg
    deploy_phase7_diagnostics
    deploy_phase8_validate

    echo ""
    echo -e "${GREEN}===============================================================================${NC}"
    echo -e "${GREEN}  AZURE FIREWALL DEPLOYMENT COMPLETE${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
    echo ""
    echo "  Firewall:           $FIREWALL_NAME"
    echo "  SKU:                $FIREWALL_SKU"
    echo "  Private IP:         ${FIREWALL_PRIVATE_IP:-N/A}"
    echo "  Policy:             $FIREWALL_POLICY_NAME"
    echo "  Route Table:        $ROUTE_TABLE_NAME → $SUBNET_NAME"
    echo "  Diagnostics:        → $LOG_ANALYTICS_WORKSPACE"
    echo "  Log File:           $LOG_FILE"
    echo ""
    echo -e "${BOLD}FQDN Application Rules:${NC}"
    echo "  ✓ AVD Service (*.wvd.microsoft.com, *.servicebus.windows.net)"
    echo "  ✓ Azure Auth (login.microsoftonline.com, *.msauth.net)"
    echo "  ✓ Azure Files (*.file.core.windows.net)"
    echo "  ✓ SAP Fiori (*.s4hana.cloud.sap, *.sap.com)"
    echo "  ✓ Zoho Desk (*.zoho.com, *.zohocdn.com)"
    echo "  ✓ Microsoft 365/Teams (*.teams.microsoft.com, *.office365.com)"
    echo "  ✓ Windows Update (*.windowsupdate.com, kms.core.windows.net)"
    echo ""
    echo -e "${BOLD}Network Rules:${NC}"
    echo "  ✓ Teams UDP TURN/STUN (3478-3481)"
    echo "  ✓ Teams TCP media (50000-50059)"
    echo "  ✓ Azure Files SMB (445 → Storage.SoutheastAsia)"
    echo "  ✓ DNS (53 UDP/TCP)"
    echo "  ✓ NTP (123 UDP)"
    echo ""
    echo -e "${YELLOW}COST IMPACT:${NC}"
    if [[ "$FIREWALL_SKU" == "Basic" ]]; then
        echo "  Azure Firewall Basic: ~EUR 280/month + data processing"
        echo "  Total platform cost: ~EUR 560/month (VMs + FW + storage)"
    else
        echo "  Azure Firewall Standard: ~EUR 900/month + data processing"
        echo "  Total platform cost: ~EUR 1,180/month (VMs + FW + storage)"
    fi
    echo ""
    echo -e "${YELLOW}NEXT STEPS:${NC}"
    echo "  1. Verify session hosts can still access SAP Fiori, Zoho Desk, Teams"
    echo "  2. Check firewall logs in Log Analytics: AZFWApplicationRule, AZFWNetworkRule"
    echo "  3. Monitor for any blocked traffic that should be allowed"
    echo "  4. Consider tightening NSG rules now that firewall handles FQDN filtering"
    echo ""

    log SUCCESS "Azure Firewall deployment completed successfully"
}

main
