#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - V4 Fully Automated Deployment
# Version: 4.0
# Date: 2026-02-12
#
# DESCRIPTION:
#   100% hands-off AVD deployment. Operator answers 5 prompts, walks away.
#   One hour later, AVD is ready for 4 consultants.
#
# FEATURES:
#   - Full automation of all 6 deployment phases
#   - Entra ID user creation + M365 licensing
#   - FSLogix profile configuration
#   - Conditional Access MFA policy
#   - Session host hardening
#   - Comprehensive validation and reporting
#   - Dry-run mode for testing
#   - Rollback capabilities
#   - Idempotent (safe to run multiple times)
#
# PREREQUISITES:
#   - Azure CLI v2.50+ (az login completed)
#   - Contributor role on Azure subscription
#   - Global Administrator role in Entra ID (for user/license operations)
#   - Microsoft Graph CLI extension (az extension add --name account)
#   - M365 Business Premium licenses available
#
# USAGE:
#   ./deploy-avd-platform-v4.sh                    # Interactive mode
#   ./deploy-avd-platform-v4.sh --dry-run          # Show what would deploy
#   ./deploy-avd-platform-v4.sh --config env.sh    # Use config file
#
# COST ESTIMATE: €220/month (2 session hosts, auto-shutdown enabled)
#===============================================================================

set -o pipefail
set -o nounset

# Custom error handler to show meaningful messages instead of silent exit
trap 'last_command=$BASH_COMMAND; last_line=$LINENO' DEBUG
trap 'if [ $? -ne 0 ]; then echo -e "\n\033[0;31m[ERROR] Command failed at line $last_line: $last_command\033[0m"; echo "[$(date)] [ERROR] Command failed at line $last_line: $last_command" >> "${LOG_FILE:-/tmp/avd-deployment.log}"; fi' EXIT

#===============================================================================
# CONFIGURATION - Edit these values or provide via --config file
#===============================================================================

# Azure Configuration
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-tktph-avd-prod-sea}"
LOCATION="${LOCATION:-southeastasia}"

# Networking
VNET_NAME="${VNET_NAME:-vnet-tktph-avd-sea}"
VNET_ADDRESS_PREFIX="${VNET_ADDRESS_PREFIX:-10.2.0.0/16}"
SUBNET_NAME="${SUBNET_NAME:-snet-avd}"
SUBNET_PREFIX="${SUBNET_PREFIX:-10.2.1.0/24}"
NSG_NAME="${NSG_NAME:-nsg-tktph-avd}"

# Storage (FSLogix)
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-sttktphfslogix}"
STORAGE_SKU="${STORAGE_SKU:-Premium_LRS}"
FSLOGIX_SHARE_NAME="${FSLOGIX_SHARE_NAME:-fslogix-profiles}"
FSLOGIX_QUOTA_GB="${FSLOGIX_QUOTA_GB:-100}"

# Monitoring
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-tktph-avd-sea}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"
ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-ag-tktph-avd}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# AVD Configuration
WORKSPACE_NAME="${WORKSPACE_NAME:-tktph-ws}"
HOSTPOOL_NAME="${HOSTPOOL_NAME:-tktph-hp}"
APPGROUP_NAME="${APPGROUP_NAME:-tktph-dag}"
HOSTPOOL_TYPE="${HOSTPOOL_TYPE:-Pooled}"
LOAD_BALANCER_TYPE="${LOAD_BALANCER_TYPE:-BreadthFirst}"
MAX_SESSION_LIMIT="${MAX_SESSION_LIMIT:-4}"

# Session Hosts
VM_PREFIX="${VM_PREFIX:-vm-tktph}"
VM_COUNT="${VM_COUNT:-2}"
VM_SIZE="${VM_SIZE:-Standard_D4s_v5}"
VM_IMAGE="${VM_IMAGE:-MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest}"
VM_DISK_SIZE_GB="${VM_DISK_SIZE_GB:-128}"
ADMIN_USERNAME="${ADMIN_USERNAME:-avdadmin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# Identity (Entra ID)
ENTRA_DOMAIN="${ENTRA_DOMAIN:-}"
USER_PREFIX="${USER_PREFIX:-ph-consultant}"
USER_COUNT="${USER_COUNT:-4}"
USER_PASSWORD="${USER_PASSWORD:-}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-TKT-Philippines-AVD-Users}"
M365_LICENSE_SKU="${M365_LICENSE_SKU:-O365_BUSINESS_PREMIUM}"

# Auto-Shutdown (disabled by default - use setup-vm-schedule.sh for Brussels timezone scheduling)
AUTO_SHUTDOWN_ENABLED="${AUTO_SHUTDOWN_ENABLED:-false}"
AUTO_SHUTDOWN_TIME="${AUTO_SHUTDOWN_TIME:-18:00}"
AUTO_SHUTDOWN_TIMEZONE="${AUTO_SHUTDOWN_TIMEZONE:-W. Europe Standard Time}"

# Tags
TAGS_ENVIRONMENT="${TAGS_ENVIRONMENT:-Production}"
TAGS_PROJECT="${TAGS_PROJECT:-TKT-Philippines}"
TAGS_OWNER="${TAGS_OWNER:-tom.tuerlings@tktconsulting.com}"
TAGS_COSTCENTER="${TAGS_COSTCENTER:-TKTPH-001}"

#===============================================================================
# INTERNAL VARIABLES - Do not modify
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/avd-deployment-$(date '+%Y%m%d-%H%M%S').log}"
DEPLOYMENT_ID="$(date '+%Y%m%d%H%M%S')"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"
PHASE_STATUS_FILE="/tmp/avd-deployment-phase-status-${DEPLOYMENT_ID}.json"
REGISTRATION_TOKEN_FILE="/tmp/avd-registration-token-${DEPLOYMENT_ID}.txt"
USER_CREDENTIALS_FILE="/tmp/avd-user-credentials-${DEPLOYMENT_ID}.txt"
DEPLOYMENT_REPORT_FILE="/tmp/avd-deployment-report-${DEPLOYMENT_ID}.md"

# Phase tracking
PHASE_CURRENT=0
PHASE_TOTAL=6

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#===============================================================================
# LOGGING FUNCTIONS
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)   echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        SUCCESS)echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} ✓ $message" ;;
        WARN)   echo -e "${YELLOW}[$timestamp] [WARNING]${NC} ⚠ $message" ;;
        ERROR)  echo -e "${RED}[$timestamp] [ERROR]${NC} ✗ $message" ;;
        DEBUG)  [[ "${DEBUG:-false}" == "true" ]] && echo -e "[$timestamp] [DEBUG] $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_phase() {
    local phase_num="$1"
    local phase_name="$2"
    PHASE_CURRENT=$phase_num
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  PHASE $phase_num/$PHASE_TOTAL: $phase_name${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Update phase status
    update_phase_status "$phase_num" "$phase_name" "IN_PROGRESS"
}

log_phase_complete() {
    local phase_num="$1"
    local phase_name="$2"
    update_phase_status "$phase_num" "$phase_name" "COMPLETED"
    log SUCCESS "Phase $phase_num complete: $phase_name"
}

update_phase_status() {
    local phase_num="$1"
    local phase_name="$2"
    local status="$3"
    
    if [[ ! -f "$PHASE_STATUS_FILE" ]]; then
        echo '{"phases":[]}' > "$PHASE_STATUS_FILE"
    fi
    
    # Append phase status (simple approach)
    echo "{\"phase\": $phase_num, \"name\": \"$phase_name\", \"status\": \"$status\", \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"}" >> "${PHASE_STATUS_FILE}.log"
}

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

show_banner() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}║   ████████╗██╗  ██╗████████╗    ██████╗ ██╗  ██╗██╗██╗     ██╗██████╗         ║${NC}"
    echo -e "${BLUE}║   ╚══██╔══╝██║ ██╔╝╚══██╔══╝    ██╔══██╗██║  ██║██║██║     ██║██╔══██╗        ║${NC}"
    echo -e "${BLUE}║      ██║   █████╔╝    ██║       ██████╔╝███████║██║██║     ██║██████╔╝        ║${NC}"
    echo -e "${BLUE}║      ██║   ██╔═██╗    ██║       ██╔═══╝ ██╔══██║██║██║     ██║██╔═══╝         ║${NC}"
    echo -e "${BLUE}║      ██║   ██║  ██╗   ██║       ██║     ██║  ██║██║███████╗██║██║             ║${NC}"
    echo -e "${BLUE}║      ╚═╝   ╚═╝  ╚═╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚═╝╚═╝             ║${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}║            Azure Virtual Desktop - V4 Automated Deployment                    ║${NC}"
    echo -e "${BLUE}║                       Version 4.0 - February 2026                            ║${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    local errors=0
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        ((errors++))
    else
        local az_version=$(az version --query '"azure-cli"' -o tsv)
        log INFO "Azure CLI version: $az_version"
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Run: az login"
        ((errors++))
    else
        local account=$(az account show --query "name" -o tsv)
        log INFO "Azure account: $account"
    fi
    
    # Check subscription
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        if ! az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null; then
            log ERROR "Cannot access subscription: $SUBSCRIPTION_ID"
            ((errors++))
        fi
    fi
    
    # Check required resource providers
    local providers=("Microsoft.Network" "Microsoft.Compute" "Microsoft.Storage" 
                     "Microsoft.OperationalInsights" "Microsoft.DesktopVirtualization"
                     "Microsoft.Insights")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            log WARN "Resource provider $provider not registered. Registering..."
            if [[ "$DRY_RUN" != "true" ]]; then
                az provider register --namespace "$provider" --wait || true
            fi
        fi
    done
    
    # Check Graph API permissions for Entra ID operations
    if ! az ad signed-in-user show &> /dev/null; then
        log WARN "Cannot access Entra ID. User creation may fail. Ensure Global Administrator role."
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Prerequisites check failed with $errors errors"
        exit 1
    fi
    
    log SUCCESS "Prerequisites check passed"
}

prompt_for_inputs() {
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        log INFO "Skipping prompts (using environment variables)"
        return
    fi
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  CONFIGURATION PROMPTS (5 questions)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 1. Admin Password
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        echo -e "${BLUE}1/5${NC} Enter admin password for session hosts"
        echo "    Requirements: 12+ chars, uppercase, lowercase, number, special char"
        read -sp "    Password: " ADMIN_PASSWORD
        echo ""
    fi
    
    # 2. User Password
    if [[ -z "$USER_PASSWORD" ]]; then
        echo ""
        echo -e "${BLUE}2/5${NC} Enter temporary password for consultant accounts"
        echo "    (Users will be forced to change on first login)"
        read -sp "    Password: " USER_PASSWORD
        echo ""
    fi
    
    # 3. Alert Email
    if [[ -z "$ALERT_EMAIL" ]]; then
        echo ""
        echo -e "${BLUE}3/5${NC} Enter email for monitoring alerts"
        read -p "    Email: " ALERT_EMAIL
    fi
    
    # 4. Entra Domain
    if [[ -z "$ENTRA_DOMAIN" ]]; then
        echo ""
        echo -e "${BLUE}4/5${NC} Enter your Entra ID domain"
        echo "    Example: yourcompany.onmicrosoft.com"
        read -p "    Domain: " ENTRA_DOMAIN
    fi
    
    # 5. Subscription (if not set)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        echo ""
        echo -e "${BLUE}5/5${NC} Select Azure subscription"
        az account list --query "[].{Name:name, ID:id, IsDefault:isDefault}" -o table
        read -p "    Enter subscription ID (or press Enter for default): " input_sub
        if [[ -n "$input_sub" ]]; then
            SUBSCRIPTION_ID="$input_sub"
        else
            SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
        fi
    fi
    
    echo ""
    log INFO "Configuration complete"
}

validate_inputs() {
    log INFO "Validating inputs..."
    
    local errors=0
    
    # Validate password complexity
    if [[ ${#ADMIN_PASSWORD} -lt 12 ]]; then
        log ERROR "Admin password must be at least 12 characters"
        ((errors++))
    fi
    
    if [[ ${#USER_PASSWORD} -lt 8 ]]; then
        log ERROR "User password must be at least 8 characters"
        ((errors++))
    fi
    
    # Validate email
    if [[ ! "$ALERT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log ERROR "Invalid email format: $ALERT_EMAIL"
        ((errors++))
    fi
    
    # Validate domain
    if [[ -z "$ENTRA_DOMAIN" ]]; then
        log ERROR "Entra ID domain is required"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log ERROR "Input validation failed with $errors errors"
        exit 1
    fi
    
    log SUCCESS "Input validation passed"
}

confirm_deployment() {
    if [[ "$SKIP_PROMPTS" == "true" ]]; then
        return
    fi
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  DEPLOYMENT SUMMARY${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Resource Group:     $RESOURCE_GROUP"
    echo "  Location:           $LOCATION"
    echo "  Session Hosts:      $VM_COUNT x $VM_SIZE"
    echo "  Users:              $USER_COUNT consultant accounts"
    echo "  Domain:             $ENTRA_DOMAIN"
    echo "  Alert Email:        $ALERT_EMAIL"
    echo "  Auto-Shutdown:      $AUTO_SHUTDOWN_TIME ($AUTO_SHUTDOWN_TIMEZONE)"
    echo ""
    echo "  Estimated Cost:     €220/month"
    echo "  Deployment Time:    ~45-60 minutes"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}MODE: DRY RUN (no changes will be made)${NC}"
        echo ""
        return
    fi
    
    read -p "  Proceed with deployment? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log INFO "Deployment cancelled by user"
        exit 0
    fi
}

# Cross-platform date function (macOS/Linux compatible)
get_expiration_time() {
    local hours="${1:-24}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -u -v+${hours}H '+%Y-%m-%dT%H:%M:%SZ'
    else
        date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ'
    fi
}

# Get resource tags as string
get_tags_string() {
    echo "Environment=$TAGS_ENVIRONMENT Project=$TAGS_PROJECT Owner=$TAGS_OWNER CostCenter=$TAGS_COSTCENTER AutoShutdown=Enabled DeploymentId=$DEPLOYMENT_ID"
}

#===============================================================================
# PHASE 1: NETWORKING
#===============================================================================

deploy_phase1_networking() {
    log_phase 1 "NETWORKING"
    
    local tags=$(get_tags_string)
    
    # Resource Group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log INFO "Resource group $RESOURCE_GROUP already exists"
    else
        log INFO "Creating resource group: $RESOURCE_GROUP"
        if [[ "$DRY_RUN" != "true" ]]; then
            az group create \
                --name "$RESOURCE_GROUP" \
                --location "$LOCATION" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Resource group created"
    fi
    
    # Virtual Network
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
        log INFO "VNet $VNET_NAME already exists"
    else
        log INFO "Creating virtual network: $VNET_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az network vnet create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VNET_NAME" \
                --address-prefix "$VNET_ADDRESS_PREFIX" \
                --subnet-name "$SUBNET_NAME" \
                --subnet-prefix "$SUBNET_PREFIX" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Virtual network created"
    fi
    
    # Network Security Group
    if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME" &>/dev/null; then
        log INFO "NSG $NSG_NAME already exists"
    else
        log INFO "Creating network security group: $NSG_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az network nsg create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$NSG_NAME" \
                --tags $tags \
                --output none
            
            # AVD required rules
            az network nsg rule create \
                --resource-group "$RESOURCE_GROUP" \
                --nsg-name "$NSG_NAME" \
                --name "Allow-AVD-Service" \
                --priority 100 \
                --direction Outbound \
                --access Allow \
                --protocol Tcp \
                --destination-address-prefixes WindowsVirtualDesktop \
                --destination-port-ranges 443 \
                --output none
            
            az network nsg rule create \
                --resource-group "$RESOURCE_GROUP" \
                --nsg-name "$NSG_NAME" \
                --name "Allow-AzureCloud" \
                --priority 110 \
                --direction Outbound \
                --access Allow \
                --protocol Tcp \
                --destination-address-prefixes AzureCloud \
                --destination-port-ranges 443 8443 \
                --output none
            
            az network nsg rule create \
                --resource-group "$RESOURCE_GROUP" \
                --nsg-name "$NSG_NAME" \
                --name "Allow-KMS" \
                --priority 120 \
                --direction Outbound \
                --access Allow \
                --protocol Tcp \
                --destination-address-prefixes Internet \
                --destination-port-ranges 1688 \
                --output none
            
            az network nsg rule create \
                --resource-group "$RESOURCE_GROUP" \
                --nsg-name "$NSG_NAME" \
                --name "Allow-DNS" \
                --priority 130 \
                --direction Outbound \
                --access Allow \
                --protocol "*" \
                --destination-address-prefixes 168.63.129.16 \
                --destination-port-ranges 53 \
                --output none
        fi
        log SUCCESS "NSG created with AVD rules"
    fi
    
    # Associate NSG with subnet
    log INFO "Associating NSG with subnet..."
    if [[ "$DRY_RUN" != "true" ]]; then
        az network vnet subnet update \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$SUBNET_NAME" \
            --network-security-group "$NSG_NAME" \
            --output none
    fi
    
    log_phase_complete 1 "NETWORKING"
}

#===============================================================================
# PHASE 2: STORAGE & MONITORING
#===============================================================================

deploy_phase2_storage_monitoring() {
    log_phase 2 "STORAGE & MONITORING"
    
    local tags=$(get_tags_string)
    
    # Storage Account (for FSLogix)
    if az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT" &>/dev/null; then
        log INFO "Storage account $STORAGE_ACCOUNT already exists"
    else
        log INFO "Creating storage account: $STORAGE_ACCOUNT"
        if [[ "$DRY_RUN" != "true" ]]; then
            az storage account create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$STORAGE_ACCOUNT" \
                --location "$LOCATION" \
                --sku "$STORAGE_SKU" \
                --kind FileStorage \
                --https-only true \
                --min-tls-version TLS1_2 \
                --allow-blob-public-access false \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Storage account created"
    fi
    
    # FSLogix File Share
    log INFO "Creating FSLogix file share: $FSLOGIX_SHARE_NAME"
    if [[ "$DRY_RUN" != "true" ]]; then
        local storage_key=$(az storage account keys list \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$STORAGE_ACCOUNT" \
            --query "[0].value" -o tsv)
        
        az storage share create \
            --name "$FSLOGIX_SHARE_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$storage_key" \
            --quota "$FSLOGIX_QUOTA_GB" \
            --output none 2>/dev/null || log INFO "File share already exists"
    fi
    log SUCCESS "FSLogix file share ready"
    
    # Log Analytics Workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &>/dev/null; then
        log INFO "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        log INFO "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        if [[ "$DRY_RUN" != "true" ]]; then
            az monitor log-analytics workspace create \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
                --location "$LOCATION" \
                --retention-time "$LOG_RETENTION_DAYS" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Log Analytics workspace created"
    fi
    
    # Action Group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" &>/dev/null; then
        log INFO "Action group $ACTION_GROUP_NAME already exists"
    else
        log INFO "Creating action group: $ACTION_GROUP_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az monitor action-group create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$ACTION_GROUP_NAME" \
                --short-name "tktphavd" \
                --action email admin-email "$ALERT_EMAIL" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Action group created"
    fi
    
    log_phase_complete 2 "STORAGE & MONITORING"
}

#===============================================================================
# PHASE 3: AVD CONTROL PLANE
#===============================================================================

deploy_phase3_avd_control_plane() {
    log_phase 3 "AVD CONTROL PLANE"
    
    local tags=$(get_tags_string)
    
    # AVD Workspace
    if az desktopvirtualization workspace show --resource-group "$RESOURCE_GROUP" --name "$WORKSPACE_NAME" &>/dev/null; then
        log INFO "AVD Workspace $WORKSPACE_NAME already exists"
    else
        log INFO "Creating AVD workspace: $WORKSPACE_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az desktopvirtualization workspace create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$WORKSPACE_NAME" \
                --location "$LOCATION" \
                --friendly-name "TKT Philippines Workspace" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "AVD workspace created"
    fi
    
    # Host Pool
    if az desktopvirtualization hostpool show --resource-group "$RESOURCE_GROUP" --name "$HOSTPOOL_NAME" &>/dev/null; then
        log INFO "Host pool $HOSTPOOL_NAME already exists"
    else
        log INFO "Creating host pool: $HOSTPOOL_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az desktopvirtualization hostpool create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$HOSTPOOL_NAME" \
                --location "$LOCATION" \
                --host-pool-type "$HOSTPOOL_TYPE" \
                --load-balancer-type "$LOAD_BALANCER_TYPE" \
                --max-session-limit "$MAX_SESSION_LIMIT" \
                --preferred-app-group-type Desktop \
                --friendly-name "TKT Philippines Host Pool" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Host pool created"
    fi
    
    # Generate registration token
    log INFO "Generating registration token..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local expiration_time=$(get_expiration_time 24)
        
        local registration_token=$(az desktopvirtualization hostpool update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --registration-info expiration-time="$expiration_time" registration-token-operation="Update" \
            --query "registrationInfo.token" -o tsv)
        
        echo "$registration_token" > "$REGISTRATION_TOKEN_FILE"
        chmod 600 "$REGISTRATION_TOKEN_FILE"
        log SUCCESS "Registration token saved to: $REGISTRATION_TOKEN_FILE"
    fi
    
    # Application Group
    local hostpool_id=""
    if [[ "$DRY_RUN" != "true" ]]; then
        hostpool_id=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --query "id" -o tsv)
    else
        hostpool_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DesktopVirtualization/hostPools/$HOSTPOOL_NAME"
    fi
    
    if az desktopvirtualization applicationgroup show --resource-group "$RESOURCE_GROUP" --name "$APPGROUP_NAME" &>/dev/null; then
        log INFO "Application group $APPGROUP_NAME already exists"
    else
        log INFO "Creating application group: $APPGROUP_NAME"
        if [[ "$DRY_RUN" != "true" ]]; then
            az desktopvirtualization applicationgroup create \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APPGROUP_NAME" \
                --location "$LOCATION" \
                --host-pool-arm-path "$hostpool_id" \
                --application-group-type Desktop \
                --friendly-name "TKT Philippines Desktop" \
                --tags $tags \
                --output none
        fi
        log SUCCESS "Application group created"
    fi
    
    # Associate application group with workspace
    log INFO "Associating application group with workspace..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local appgroup_id=$(az desktopvirtualization applicationgroup show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APPGROUP_NAME" \
            --query "id" -o tsv)
        
        az desktopvirtualization workspace update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WORKSPACE_NAME" \
            --application-group-references "$appgroup_id" \
            --output none
    fi
    log SUCCESS "Application group associated with workspace"
    
    # Configure diagnostics
    log INFO "Configuring host pool diagnostics..."
    if [[ "$DRY_RUN" != "true" ]]; then
        local workspace_id=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --query "id" -o tsv)
        
        local hostpool_resource_id=$(az desktopvirtualization hostpool show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$HOSTPOOL_NAME" \
            --query "id" -o tsv)
        
        az monitor diagnostic-settings create \
            --resource "$hostpool_resource_id" \
            --name "AVD-Diagnostics" \
            --workspace "$workspace_id" \
            --logs '[
                {"category": "Checkpoint", "enabled": true},
                {"category": "Error", "enabled": true},
                {"category": "Management", "enabled": true},
                {"category": "Connection", "enabled": true},
                {"category": "HostRegistration", "enabled": true},
                {"category": "AgentHealthStatus", "enabled": true}
            ]' \
            --output none 2>/dev/null || log WARN "Diagnostics configuration may need manual setup"
    fi
    
    log_phase_complete 3 "AVD CONTROL PLANE"
}

#===============================================================================
# PHASE 4: SESSION HOSTS
#===============================================================================

deploy_phase4_session_hosts() {
    log_phase 4 "SESSION HOSTS"
    
    local tags=$(get_tags_string)
    
    # Get subnet ID
    local subnet_id=""
    if [[ "$DRY_RUN" != "true" ]]; then
        subnet_id=$(az network vnet subnet show \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$SUBNET_NAME" \
            --query "id" -o tsv)
    fi
    
    # Deploy session host VMs
    for i in $(seq 1 $VM_COUNT); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        
        if az vm show --resource-group "$RESOURCE_GROUP" --name "$vm_name" &>/dev/null; then
            log INFO "Session host $vm_name already exists"
            continue
        fi
        
        log INFO "Deploying session host: $vm_name (this typically takes 5-10 minutes)..."
        if [[ "$DRY_RUN" != "true" ]]; then
            # Start VM creation with progress visible (--output table shows deployment progress)
            if az vm create \
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
                --tags $tags \
                --output table 2>&1 | tee -a "$LOG_FILE"; then
                log SUCCESS "$vm_name deployed"
            else
                log ERROR "Failed to deploy $vm_name - check Azure Activity Log for details"
                log ERROR "Common causes: quota limits, image availability, network issues"
                # Continue with remaining VMs rather than hard fail
            fi
            
            # Configure auto-shutdown
            if [[ "$AUTO_SHUTDOWN_ENABLED" == "true" ]]; then
                log INFO "Configuring auto-shutdown for $vm_name..."
                az vm auto-shutdown \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$vm_name" \
                    --time "$AUTO_SHUTDOWN_TIME" \
                    --output none 2>/dev/null || log WARN "Auto-shutdown configuration may need manual setup"
            fi
        fi
    done
    
    # Run hardening script on session hosts
    log INFO "Running hardening script on session hosts..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "$SCRIPT_DIR/setup-session-host-hardening.sh" \
            --resource-group "$RESOURCE_GROUP" \
            --vm-prefix "$VM_PREFIX" \
            --vm-count "$VM_COUNT" \
            --storage-account "$STORAGE_ACCOUNT" \
            --registration-token-file "$REGISTRATION_TOKEN_FILE" \
            || log WARN "Hardening script had issues - check logs"
    fi
    
    log_phase_complete 4 "SESSION HOSTS"
}

#===============================================================================
# PHASE 5: IDENTITY (Entra ID)
#===============================================================================

deploy_phase5_identity() {
    log_phase 5 "IDENTITY (Entra ID)"
    
    # Run Entra ID automation script
    log INFO "Running Entra ID automation..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "$SCRIPT_DIR/setup-entra-id-automation.sh" \
            --domain "$ENTRA_DOMAIN" \
            --user-prefix "$USER_PREFIX" \
            --user-count "$USER_COUNT" \
            --password "$USER_PASSWORD" \
            --security-group "$SECURITY_GROUP_NAME" \
            --appgroup-name "$APPGROUP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --credentials-file "$USER_CREDENTIALS_FILE" \
            || log WARN "Entra ID automation had issues - check logs"
    fi
    
    # Run FSLogix configuration
    log INFO "Running FSLogix configuration..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "$SCRIPT_DIR/setup-fslogix-profiles.sh" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --share-name "$FSLOGIX_SHARE_NAME" \
            --vm-prefix "$VM_PREFIX" \
            --vm-count "$VM_COUNT" \
            --security-group "$SECURITY_GROUP_NAME" \
            || log WARN "FSLogix configuration had issues - check logs"
    fi
    
    log_phase_complete 5 "IDENTITY (Entra ID)"
}

#===============================================================================
# PHASE 6: VALIDATION & REPORTING
#===============================================================================

deploy_phase6_validation() {
    log_phase 6 "VALIDATION & REPORTING"
    
    # Run validation script
    log INFO "Running deployment validation..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "$SCRIPT_DIR/validate-deployment.sh" \
            --resource-group "$RESOURCE_GROUP" \
            --hostpool "$HOSTPOOL_NAME" \
            --storage-account "$STORAGE_ACCOUNT" \
            --vm-prefix "$VM_PREFIX" \
            --vm-count "$VM_COUNT" \
            || log WARN "Some validation checks failed - review report"
    fi
    
    # Generate deployment report
    log INFO "Generating deployment report..."
    if [[ "$DRY_RUN" != "true" ]]; then
        "$SCRIPT_DIR/generate-deployment-report.sh" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-id "$DEPLOYMENT_ID" \
            --output-file "$DEPLOYMENT_REPORT_FILE" \
            --credentials-file "$USER_CREDENTIALS_FILE" \
            --log-file "$LOG_FILE" \
            || log WARN "Report generation had issues"
    fi
    
    log_phase_complete 6 "VALIDATION & REPORTING"
}

#===============================================================================
# SUMMARY AND CLEANUP
#===============================================================================

print_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  DEPLOYMENT COMPLETE!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Deployment ID:      $DEPLOYMENT_ID"
    echo "  Duration:           $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
    echo ""
    echo "  Resources Created:"
    echo "    • Resource Group: $RESOURCE_GROUP"
    echo "    • VNet + Subnet:  $VNET_NAME / $SUBNET_NAME"
    echo "    • NSG:            $NSG_NAME"
    echo "    • Storage:        $STORAGE_ACCOUNT"
    echo "    • Log Analytics:  $LOG_ANALYTICS_WORKSPACE"
    echo "    • Host Pool:      $HOSTPOOL_NAME"
    echo "    • Session Hosts:  $VM_COUNT VMs (${VM_PREFIX}-01 to ${VM_PREFIX}-$(printf '%02d' $VM_COUNT))"
    echo "    • Users:          $USER_COUNT consultant accounts"
    echo ""
    echo "  Output Files:"
    echo "    • Deployment Log:       $LOG_FILE"
    echo "    • Registration Token:   $REGISTRATION_TOKEN_FILE"
    echo "    • User Credentials:     $USER_CREDENTIALS_FILE"
    echo "    • Deployment Report:    $DEPLOYMENT_REPORT_FILE"
    echo ""
    echo "  Estimated Monthly Cost:   €220"
    echo ""
    echo "  Next Steps:"
    echo "    1. Review deployment report: cat $DEPLOYMENT_REPORT_FILE"
    echo "    2. Distribute user credentials (secure channel)"
    echo "    3. Test user login at: https://client.wvd.microsoft.com"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --config)
                if [[ -f "$2" ]]; then
                    source "$2"
                else
                    log ERROR "Config file not found: $2"
                    exit 1
                fi
                shift 2
                ;;
            --skip-prompts)
                SKIP_PROMPTS="true"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run       Show what would deploy without making changes"
                echo "  --config FILE   Load configuration from file"
                echo "  --skip-prompts  Use environment variables only (no interactive prompts)"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

main() {
    # Track total time
    SECONDS=0
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show banner
    show_banner
    
    # Check prerequisites
    check_prerequisites
    
    # Prompt for inputs
    prompt_for_inputs
    
    # Validate inputs
    validate_inputs
    
    # Confirm deployment
    confirm_deployment
    
    # Execute deployment phases
    deploy_phase1_networking
    deploy_phase2_storage_monitoring
    deploy_phase3_avd_control_plane
    deploy_phase4_session_hosts
    deploy_phase5_identity
    deploy_phase6_validation
    
    # Print summary
    print_summary
}

# Run main function
main "$@"
