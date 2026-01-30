#!/bin/bash
#===============================================================================
# TKT Philippines SAP Platform - Azure Firewall Deployment Script
# Version: 1.0
# Date: 2026-01-30
#
# This script deploys Azure Firewall with URL filtering for the Philippines
# SAP consulting platform.
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Contributor role on subscription
#   - Existing VNet and resource group
#
# Usage:
#   chmod +x deploy-azure-firewall.sh
#   ./deploy-azure-firewall.sh
#===============================================================================

set -e  # Exit on error

#-------------------------------------------------------------------------------
# CONFIGURATION - Update these values for your environment
#-------------------------------------------------------------------------------

# Resource identifiers
CUSTOMER_NUMBER="001"
RESOURCE_GROUP="rg-customer-${CUSTOMER_NUMBER}-philippines"
LOCATION="southeastasia"

# Networking
VNET_NAME="vnet-customer-${CUSTOMER_NUMBER}-ph"
WORKSTATION_SUBNET="snet-workstations"
FIREWALL_SUBNET="AzureFirewallSubnet"  # Must be this exact name
FIREWALL_SUBNET_PREFIX="10.1.2.0/26"   # Minimum /26 for Azure Firewall

# Firewall
FIREWALL_NAME="afw-customer-${CUSTOMER_NUMBER}-ph"
FIREWALL_PIP_NAME="pip-afw-customer-${CUSTOMER_NUMBER}-ph"
FIREWALL_POLICY_NAME="afwp-customer-${CUSTOMER_NUMBER}-ph"

# Route table
ROUTE_TABLE_NAME="rt-customer-${CUSTOMER_NUMBER}-ph"

# Log Analytics (existing)
LOG_ANALYTICS_WORKSPACE="law-tkt-customer${CUSTOMER_NUMBER}-sea"

# Tags
TAGS="Customer=Customer-${CUSTOMER_NUMBER} Environment=Production Project=SAP-Consulting CostCenter=Customer-${CUSTOMER_NUMBER}-Philippines"

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        echo "ERROR: Azure CLI not found. Please install it first."
        exit 1
    fi
    
    # Check login status
    if ! az account show &> /dev/null; then
        echo "ERROR: Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo "ERROR: Resource group '$RESOURCE_GROUP' not found."
        exit 1
    fi
    
    # Verify VNet exists
    if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &> /dev/null; then
        echo "ERROR: VNet '$VNET_NAME' not found in resource group '$RESOURCE_GROUP'."
        exit 1
    fi
    
    log "Prerequisites check passed."
}

create_firewall_subnet() {
    log "Creating Azure Firewall subnet..."
    
    # Check if subnet already exists
    if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$FIREWALL_SUBNET" &> /dev/null; then
        log "Firewall subnet already exists, skipping creation."
        return
    fi
    
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$FIREWALL_SUBNET" \
        --address-prefix "$FIREWALL_SUBNET_PREFIX"
    
    log "Firewall subnet created."
}

create_public_ip() {
    log "Creating public IP for Azure Firewall..."
    
    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_PIP_NAME" \
        --location "$LOCATION" \
        --allocation-method Static \
        --sku Standard \
        --tags $TAGS
    
    log "Public IP created."
}

create_firewall_policy() {
    log "Creating Azure Firewall Policy..."
    
    az network firewall policy create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_POLICY_NAME" \
        --location "$LOCATION" \
        --sku Standard \
        --tags $TAGS
    
    log "Firewall policy created."
}

create_application_rules() {
    log "Creating application rule collections..."
    
    # Rule Collection Group
    az network firewall policy rule-collection-group create \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --name "DefaultApplicationRuleCollectionGroup" \
        --priority 100
    
    # SAP Cloud Services - ALLOW
    log "Creating SAP Cloud rules..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "DefaultApplicationRuleCollectionGroup" \
        --name "Allow-SAP-Cloud" \
        --collection-priority 100 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "SAP-Domains" \
        --protocols Https=443 \
        --source-addresses "10.1.1.0/24" \
        --target-fqdns \
            "*.sap.com" \
            "*.sapcloud.com" \
            "*.hana.ondemand.com" \
            "*.s4hana.cloud.sap" \
            "*.successfactors.com" \
            "*.ariba.com" \
            "*.concur.com"
    
    # Microsoft Services - ALLOW
    log "Creating Microsoft services rules..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "DefaultApplicationRuleCollectionGroup" \
        --name "Allow-Microsoft-Services" \
        --collection-priority 200 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "Microsoft-Domains" \
        --protocols Https=443 \
        --source-addresses "10.1.1.0/24" \
        --target-fqdns \
            "*.microsoft.com" \
            "*.microsoftonline.com" \
            "*.azure.com" \
            "*.azure.net" \
            "*.windows.net" \
            "*.office.com" \
            "*.office365.com" \
            "*.sharepoint.com" \
            "*.teams.microsoft.com" \
            "*.live.com" \
            "*.msauth.net" \
            "*.msftauth.net" \
            "*.msauthimages.net" \
            "*.msecnd.net" \
            "*.msocdn.com"
    
    # Windows Update - ALLOW
    log "Creating Windows Update rules..."
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "DefaultApplicationRuleCollectionGroup" \
        --name "Allow-Windows-Update" \
        --collection-priority 300 \
        --action Allow \
        --rule-type ApplicationRule \
        --rule-name "WindowsUpdate-Domains" \
        --protocols Https=443 Http=80 \
        --source-addresses "10.1.1.0/24" \
        --target-fqdns \
            "*.windowsupdate.com" \
            "*.update.microsoft.com" \
            "*.windowsupdate.microsoft.com" \
            "*.download.windowsupdate.com" \
            "*.ntservicepack.microsoft.com"
    
    log "Application rules created."
}

create_network_rules() {
    log "Creating network rule collections..."
    
    # Network Rule Collection Group
    az network firewall policy rule-collection-group create \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --name "DefaultNetworkRuleCollectionGroup" \
        --priority 200
    
    # DNS - Required for FQDN resolution
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "DefaultNetworkRuleCollectionGroup" \
        --name "Allow-DNS" \
        --collection-priority 100 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "DNS-Outbound" \
        --protocols UDP \
        --source-addresses "10.1.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 53
    
    # NTP - Time synchronization
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "$FIREWALL_POLICY_NAME" \
        --rule-collection-group-name "DefaultNetworkRuleCollectionGroup" \
        --name "Allow-NTP" \
        --collection-priority 110 \
        --action Allow \
        --rule-type NetworkRule \
        --rule-name "NTP-Outbound" \
        --protocols UDP \
        --source-addresses "10.1.1.0/24" \
        --destination-addresses "*" \
        --destination-ports 123
    
    log "Network rules created."
}

deploy_firewall() {
    log "Deploying Azure Firewall (this may take 5-10 minutes)..."
    
    az network firewall create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --location "$LOCATION" \
        --sku AZFW_VNet \
        --tier Standard \
        --firewall-policy "$FIREWALL_POLICY_NAME" \
        --vnet-name "$VNET_NAME" \
        --public-ip "$FIREWALL_PIP_NAME" \
        --tags $TAGS
    
    log "Azure Firewall deployed."
}

get_firewall_private_ip() {
    az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "ipConfigurations[0].privateIPAddress" \
        --output tsv
}

create_route_table() {
    log "Creating route table..."
    
    FIREWALL_PRIVATE_IP=$(get_firewall_private_ip)
    log "Firewall private IP: $FIREWALL_PRIVATE_IP"
    
    # Create route table
    az network route-table create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ROUTE_TABLE_NAME" \
        --location "$LOCATION" \
        --disable-bgp-route-propagation true \
        --tags $TAGS
    
    # Add default route to firewall
    az network route-table route create \
        --resource-group "$RESOURCE_GROUP" \
        --route-table-name "$ROUTE_TABLE_NAME" \
        --name "default-to-firewall" \
        --address-prefix "0.0.0.0/0" \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address "$FIREWALL_PRIVATE_IP"
    
    log "Route table created."
}

associate_route_table() {
    log "Associating route table with workstation subnet..."
    
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$WORKSTATION_SUBNET" \
        --route-table "$ROUTE_TABLE_NAME"
    
    log "Route table associated."
}

configure_diagnostics() {
    log "Configuring diagnostic settings..."
    
    # Get Log Analytics workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query "id" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -z "$WORKSPACE_ID" ]; then
        log "WARNING: Log Analytics workspace not found. Skipping diagnostics configuration."
        return
    fi
    
    # Get firewall resource ID
    FIREWALL_ID=$(az network firewall show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FIREWALL_NAME" \
        --query "id" \
        --output tsv)
    
    # Create diagnostic setting
    az monitor diagnostic-settings create \
        --resource "$FIREWALL_ID" \
        --name "FirewallDiagnostics" \
        --workspace "$WORKSPACE_ID" \
        --logs '[
            {"category": "AzureFirewallApplicationRule", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
            {"category": "AzureFirewallNetworkRule", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
            {"category": "AzureFirewallDnsProxy", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
        ]' \
        --metrics '[{"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}]'
    
    log "Diagnostic settings configured."
}

print_summary() {
    echo ""
    echo "==============================================================================="
    echo "                    DEPLOYMENT COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Resources Created:"
    echo "  - Firewall Subnet: $FIREWALL_SUBNET ($FIREWALL_SUBNET_PREFIX)"
    echo "  - Public IP: $FIREWALL_PIP_NAME"
    echo "  - Firewall Policy: $FIREWALL_POLICY_NAME"
    echo "  - Azure Firewall: $FIREWALL_NAME"
    echo "  - Route Table: $ROUTE_TABLE_NAME"
    echo ""
    echo "Firewall Private IP: $(get_firewall_private_ip)"
    echo ""
    echo "Allowed Domains:"
    echo "  ✓ SAP Cloud (*.sap.com, *.sapcloud.com, etc.)"
    echo "  ✓ Microsoft Services (*.microsoft.com, *.office365.com, etc.)"
    echo "  ✓ Windows Update"
    echo "  ✗ All other domains BLOCKED"
    echo ""
    echo "Next Steps:"
    echo "  1. Test connectivity from VMs to allowed domains"
    echo "  2. Verify blocked domains are denied"
    echo "  3. Check firewall logs in Log Analytics"
    echo "  4. Add customer-specific domains as needed"
    echo ""
    echo "==============================================================================="
}

#-------------------------------------------------------------------------------
# MAIN EXECUTION
#-------------------------------------------------------------------------------

main() {
    log "Starting Azure Firewall deployment for Customer $CUSTOMER_NUMBER"
    echo ""
    
    check_prerequisites
    create_firewall_subnet
    create_public_ip
    create_firewall_policy
    create_application_rules
    create_network_rules
    deploy_firewall
    create_route_table
    associate_route_table
    configure_diagnostics
    print_summary
}

# Run main function
main "$@"
