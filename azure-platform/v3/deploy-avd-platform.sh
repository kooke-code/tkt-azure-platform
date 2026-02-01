#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Automated Deployment Script
# Version: 3.0
# Date: 2026-02-01
#
# This script deploys the complete AVD infrastructure for the TKT Philippines
# SAP consulting platform.
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Contributor role on subscription
#   - M365 Business Premium licenses available
#
# Usage:
#   chmod +x deploy-avd-platform.sh
#   ./deploy-avd-platform.sh
#===============================================================================

set -e  # Exit on error

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

# Resource identifiers
RESOURCE_GROUP="rg-tktph-avd-prod-sea"
LOCATION="southeastasia"

# Networking
VNET_NAME="vnet-tktph-avd-sea"
VNET_ADDRESS="10.2.0.0/16"
SUBNET_NAME="snet-avd"
SUBNET_ADDRESS="10.2.1.0/24"
NSG_NAME="nsg-tktph-avd"

# AVD Control Plane
WORKSPACE_NAME="tktph-ws"
HOSTPOOL_NAME="tktph-hp"
APPGROUP_NAME="tktph-dag"

# Session Hosts
VM_PREFIX="vm-tktph"
VM_COUNT=2
VM_SIZE="Standard_D4s_v5"
VM_IMAGE="MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest"
ADMIN_USERNAME="avdadmin"

# Storage
STORAGE_ACCOUNT="sttktphfslogix"
FSLOGIX_SHARE="fslogix-profiles"

# Monitoring
LOG_ANALYTICS_WORKSPACE="law-tktph-avd-sea"
ACTION_GROUP_NAME="ag-tktph-avd"
ALERT_EMAIL="tom.tuerlings@tktconsulting.com"

# Tags
TAGS="Environment=Production Project=TKT-Philippines Owner=tom.tuerlings@tktconsulting.com CostCenter=TKTPH-001 AutoShutdown=Enabled"

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1" >&2
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from https://aka.ms/installazurecli"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    # Register required providers
    az provider register --namespace Microsoft.DesktopVirtualization --wait
    az provider register --namespace Microsoft.Compute --wait
    az provider register --namespace Microsoft.Storage --wait
    
    log_success "Prerequisites check passed"
}

#-------------------------------------------------------------------------------
# PHASE 1: RESOURCE GROUP & NETWORKING
#-------------------------------------------------------------------------------

deploy_networking() {
    log "=== PHASE 1: Deploying networking ==="
    
    # Create resource group
    log "Creating resource group..."
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags $TAGS \
        --output none
    log_success "Resource group created"
    
    # Create VNet
    log "Creating virtual network..."
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_ADDRESS" \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix "$SUBNET_ADDRESS" \
        --tags $TAGS \
        --output none
    log_success "Virtual network created"
    
    # Add storage service endpoint
    log "Adding storage service endpoint..."
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --service-endpoints Microsoft.Storage \
        --output none
    log_success "Service endpoint added"
    
    # Create NSG
    log "Creating network security group..."
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --tags $TAGS \
        --output none
    
    # NSG Rules
    log "Adding NSG rules..."
    
    # Allow AVD outbound
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-AVD-Outbound" \
        --priority 100 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes AzureCloud \
        --destination-port-ranges 443 \
        --output none
    
    # Allow Storage
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-Storage" \
        --priority 110 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes Storage \
        --destination-port-ranges 445 \
        --output none
    
    # Allow DNS
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-DNS" \
        --priority 120 \
        --direction Outbound \
        --access Allow \
        --protocol "*" \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes "*" \
        --destination-port-ranges 53 \
        --output none
    
    # Allow KMS
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-KMS" \
        --priority 130 \
        --direction Outbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes VirtualNetwork \
        --destination-address-prefixes "*" \
        --destination-port-ranges 1688 \
        --output none
    
    # Deny all inbound
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Deny-All-Inbound" \
        --priority 4096 \
        --direction Inbound \
        --access Deny \
        --protocol "*" \
        --source-address-prefixes "*" \
        --destination-address-prefixes "*" \
        --destination-port-ranges "*" \
        --output none
    
    # Associate NSG with subnet
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME" \
        --output none
    
    log_success "NSG created and associated"
}

#-------------------------------------------------------------------------------
# PHASE 2: STORAGE & MONITORING
#-------------------------------------------------------------------------------

deploy_storage() {
    log "=== PHASE 2: Deploying storage ==="
    
    # Create storage account for FSLogix
    log "Creating premium file storage account..."
    az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --kind FileStorage \
        --sku Premium_LRS \
        --location "$LOCATION" \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --tags $TAGS \
        --output none
    log_success "Storage account created"
    
    # Create FSLogix file share
    log "Creating FSLogix file share..."
    az storage share-rm create \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --name "$FSLOGIX_SHARE" \
        --quota 100 \
        --enabled-protocols SMB \
        --output none
    log_success "FSLogix file share created"
}

deploy_monitoring() {
    log "Deploying monitoring..."
    
    # Create Log Analytics workspace
    log "Creating Log Analytics workspace..."
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --retention-time 30 \
        --tags $TAGS \
        --output none
    log_success "Log Analytics workspace created"
    
    # Create action group
    log "Creating action group..."
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "tktph" \
        --action email admin "$ALERT_EMAIL" \
        --tags $TAGS \
        --output none
    log_success "Action group created"
}

#-------------------------------------------------------------------------------
# PHASE 3: AVD CONTROL PLANE
#-------------------------------------------------------------------------------

deploy_avd_control_plane() {
    log "=== PHASE 3: Deploying AVD control plane ==="
    
    # Create workspace
    log "Creating AVD workspace..."
    az desktopvirtualization workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --friendly-name "TKT Philippines Workspace" \
        --description "AVD workspace for Philippines SAP consultants" \
        --tags $TAGS \
        --output none
    log_success "Workspace created"
    
    # Create host pool
    log "Creating host pool..."
    az desktopvirtualization hostpool create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --location "$LOCATION" \
        --host-pool-type Pooled \
        --load-balancer-type BreadthFirst \
        --max-session-limit 2 \
        --preferred-app-group-type Desktop \
        --start-vm-on-connect true \
        --friendly-name "TKT Philippines Host Pool" \
        --tags $TAGS \
        --output none
    log_success "Host pool created"
    
    # Generate registration token
    log "Generating registration token..."
    EXPIRATION_TIME=$(date -u -d '+24 hours' '+%Y-%m-%dT%H:%M:%SZ')
    REGISTRATION_TOKEN=$(az desktopvirtualization hostpool update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --registration-info expiration-time="$EXPIRATION_TIME" registration-token-operation="Update" \
        --query "registrationInfo.token" \
        --output tsv)
    
    # Save token to file
    echo "$REGISTRATION_TOKEN" > /tmp/avd-registration-token.txt
    log_success "Registration token saved to /tmp/avd-registration-token.txt"
    
    # Get host pool resource ID
    HOSTPOOL_ID=$(az desktopvirtualization hostpool show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --query "id" \
        --output tsv)
    
    # Create application group
    log "Creating application group..."
    az desktopvirtualization applicationgroup create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APPGROUP_NAME" \
        --location "$LOCATION" \
        --host-pool-arm-path "$HOSTPOOL_ID" \
        --application-group-type Desktop \
        --friendly-name "TKT Philippines Desktop" \
        --tags $TAGS \
        --output none
    log_success "Application group created"
    
    # Get application group resource ID
    APPGROUP_ID=$(az desktopvirtualization applicationgroup show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APPGROUP_NAME" \
        --query "id" \
        --output tsv)
    
    # Associate application group with workspace
    log "Associating application group with workspace..."
    az desktopvirtualization workspace update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WORKSPACE_NAME" \
        --application-group-references "$APPGROUP_ID" \
        --output none
    log_success "Application group associated with workspace"
}

#-------------------------------------------------------------------------------
# PHASE 4: SESSION HOSTS
#-------------------------------------------------------------------------------

deploy_session_hosts() {
    log "=== PHASE 4: Deploying session hosts ==="
    
    # Prompt for admin password
    echo ""
    echo "Enter admin password for session hosts (min 12 chars, complex):"
    read -s ADMIN_PASSWORD
    echo ""
    
    # Get subnet ID
    SUBNET_ID=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --query "id" \
        --output tsv)
    
    for i in $(seq 1 $VM_COUNT); do
        VM_NAME="${VM_PREFIX}-$(printf '%02d' $i)"
        log "Deploying session host: $VM_NAME..."
        
        az vm create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --image "$VM_IMAGE" \
            --size "$VM_SIZE" \
            --admin-username "$ADMIN_USERNAME" \
            --admin-password "$ADMIN_PASSWORD" \
            --subnet "$SUBNET_ID" \
            --public-ip-address "" \
            --nsg "" \
            --os-disk-size-gb 128 \
            --storage-sku Premium_LRS \
            --tags $TAGS \
            --output none
        
        log_success "$VM_NAME deployed"
    done
    
    log ""
    log "================================================================"
    log "SESSION HOST DEPLOYMENT COMPLETE"
    log "================================================================"
    log ""
    log "IMPORTANT: You must now manually:"
    log "1. Connect to each VM (use Azure Serial Console or temporary Bastion)"
    log "2. Install AVD Agent: https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    log "3. Install AVD Bootloader: https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    log "4. Use registration token from: /tmp/avd-registration-token.txt"
    log "5. Install and configure FSLogix"
    log ""
    log "Registration token (valid 24 hours):"
    cat /tmp/avd-registration-token.txt
    log ""
}

#-------------------------------------------------------------------------------
# PHASE 5: CONFIGURE DIAGNOSTICS
#-------------------------------------------------------------------------------

configure_diagnostics() {
    log "=== PHASE 5: Configuring diagnostics ==="
    
    # Get Log Analytics workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" \
        --output tsv)
    
    # Get host pool resource ID
    HOSTPOOL_RESOURCE_ID=$(az desktopvirtualization hostpool show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --query "id" \
        --output tsv)
    
    # Configure diagnostics for host pool
    log "Configuring host pool diagnostics..."
    az monitor diagnostic-settings create \
        --resource "$HOSTPOOL_RESOURCE_ID" \
        --name "AVD-Diagnostics" \
        --workspace "$WORKSPACE_ID" \
        --logs '[
            {"category": "Checkpoint", "enabled": true},
            {"category": "Error", "enabled": true},
            {"category": "Management", "enabled": true},
            {"category": "Connection", "enabled": true},
            {"category": "HostRegistration", "enabled": true},
            {"category": "AgentHealthStatus", "enabled": true}
        ]' \
        --output none 2>/dev/null || log "Note: Diagnostics may need portal configuration"
    
    log_success "Diagnostics configured"
}

#-------------------------------------------------------------------------------
# SUMMARY
#-------------------------------------------------------------------------------

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    AVD DEPLOYMENT COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Resources Created:"
    echo "  Resource Group:    $RESOURCE_GROUP"
    echo "  Virtual Network:   $VNET_NAME ($VNET_ADDRESS)"
    echo "  NSG:               $NSG_NAME"
    echo "  Storage Account:   $STORAGE_ACCOUNT"
    echo "  FSLogix Share:     $FSLOGIX_SHARE (100GB)"
    echo "  Log Analytics:     $LOG_ANALYTICS_WORKSPACE"
    echo "  AVD Workspace:     $WORKSPACE_NAME"
    echo "  Host Pool:         $HOSTPOOL_NAME"
    echo "  Application Group: $APPGROUP_NAME"
    echo "  Session Hosts:     $VM_COUNT VMs ($VM_SIZE)"
    echo ""
    echo "==============================================================================="
    echo "                    NEXT STEPS (MANUAL)"
    echo "==============================================================================="
    echo ""
    echo "1. Configure session hosts:"
    echo "   - Install AVD Agent + Bootloader"
    echo "   - Configure FSLogix"
    echo "   - Registration token: /tmp/avd-registration-token.txt"
    echo ""
    echo "2. Configure identity:"
    echo "   - Create security group: TKT-Philippines-AVD-Users"
    echo "   - Create user accounts"
    echo "   - Assign M365 licenses"
    echo "   - Configure Conditional Access (MFA)"
    echo ""
    echo "3. Configure auto-shutdown:"
    echo "   - Deploy Start/Stop VMs v2 solution"
    echo "   - Schedule: 08:00-18:00 PHT, Mon-Fri"
    echo ""
    echo "4. Run validation checklist:"
    echo "   - See: validation-checklist.md"
    echo ""
    echo "==============================================================================="
    echo "                    ESTIMATED MONTHLY COST: €220"
    echo "==============================================================================="
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "==============================================================================="
    echo "     TKT PHILIPPINES AVD PLATFORM - AUTOMATED DEPLOYMENT"
    echo "     Version 3.0"
    echo "==============================================================================="
    echo ""
    
    check_prerequisites
    deploy_networking
    deploy_storage
    deploy_monitoring
    deploy_avd_control_plane
    deploy_session_hosts
    configure_diagnostics
    print_summary
}

# Run main function
main "$@"
