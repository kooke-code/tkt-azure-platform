#!/bin/bash
#===============================================================================
# TKT Philippines SAP Platform - Azure Files Setup Script
# Version: 1.0
# Date: 2026-01-30
#
# This script configures Azure Files for the consultant knowledge base and
# redirected folders.
#
# Usage:
#   chmod +x setup-azure-files.sh
#   ./setup-azure-files.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

CUSTOMER_NUMBER="001"
RESOURCE_GROUP="rg-customer-${CUSTOMER_NUMBER}-philippines"
STORAGE_ACCOUNT="stcustomer${CUSTOMER_NUMBER}ph"
LOCATION="southeastasia"

# File shares
SHARE_NAME="consultant-data"
SHARE_QUOTA="100"  # GB

# Users (update based on your Azure AD users)
USERS=("ph-lead-001" "ph-consultant-001" "ph-consultant-002" "ph-consultant-003")

TAGS="Customer=Customer-${CUSTOMER_NUMBER} Environment=Production Project=SAP-Consulting"

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

configure_storage_security() {
    log "Configuring storage account security..."
    
    # Enable secure transfer (HTTPS only)
    az storage account update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false
    
    log "Storage security configured."
}

create_file_share() {
    log "Creating file share: $SHARE_NAME..."
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query "[0].value" \
        --output tsv)
    
    # Create file share
    az storage share create \
        --name "$SHARE_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --quota "$SHARE_QUOTA"
    
    log "File share created."
}

create_folder_structure() {
    log "Creating folder structure..."
    
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query "[0].value" \
        --output tsv)
    
    # Create user folders
    for USER in "${USERS[@]}"; do
        log "Creating folders for user: $USER"
        
        az storage directory create \
            --name "$USER" \
            --share-name "$SHARE_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" 2>/dev/null || true
        
        az storage directory create \
            --name "$USER/Desktop" \
            --share-name "$SHARE_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" 2>/dev/null || true
        
        az storage directory create \
            --name "$USER/Documents" \
            --share-name "$SHARE_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" 2>/dev/null || true
        
        az storage directory create \
            --name "$USER/Downloads" \
            --share-name "$SHARE_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" 2>/dev/null || true
    done
    
    # Create shared folders
    log "Creating shared folders..."
    
    az storage directory create \
        --name "_shared" \
        --share-name "$SHARE_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" 2>/dev/null || true
    
    az storage directory create \
        --name "_shared/knowledge-base" \
        --share-name "$SHARE_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" 2>/dev/null || true
    
    az storage directory create \
        --name "_shared/templates" \
        --share-name "$SHARE_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" 2>/dev/null || true
    
    az storage directory create \
        --name "_shared/project-files" \
        --share-name "$SHARE_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" 2>/dev/null || true
    
    log "Folder structure created."
}

enable_soft_delete() {
    log "Enabling soft delete for file shares..."
    
    az storage account file-service-properties update \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --enable-delete-retention true \
        --delete-retention-days 14
    
    log "Soft delete enabled (14 days retention)."
}

create_screen_recordings_container() {
    log "Creating blob container for screen recordings..."
    
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query "[0].value" \
        --output tsv)
    
    az storage container create \
        --name "screen-recordings" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    log "Screen recordings container created."
}

print_mount_instructions() {
    echo ""
    echo "==============================================================================="
    echo "                    AZURE FILES SETUP COMPLETE"
    echo "==============================================================================="
    echo ""
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "File Share: $SHARE_NAME"
    echo "Quota: ${SHARE_QUOTA}GB"
    echo ""
    echo "Folder Structure:"
    echo "  ├── ph-lead-001/"
    echo "  │   ├── Desktop/"
    echo "  │   ├── Documents/"
    echo "  │   └── Downloads/"
    echo "  ├── ph-consultant-001/"
    echo "  ├── ph-consultant-002/"
    echo "  ├── ph-consultant-003/"
    echo "  └── _shared/"
    echo "      ├── knowledge-base/"
    echo "      ├── templates/"
    echo "      └── project-files/"
    echo ""
    echo "==============================================================================="
    echo "                    MOUNT INSTRUCTIONS FOR VMs"
    echo "==============================================================================="
    echo ""
    echo "Run this PowerShell command on each VM to mount the share as Z: drive:"
    echo ""
    
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query "[0].value" \
        --output tsv)
    
    echo "# PowerShell - Mount Azure Files"
    echo "\$connectTestResult = Test-NetConnection -ComputerName ${STORAGE_ACCOUNT}.file.core.windows.net -Port 445"
    echo "if (\$connectTestResult.TcpTestSucceeded) {"
    echo "    cmd.exe /C \"cmdkey /add:${STORAGE_ACCOUNT}.file.core.windows.net /user:Azure\\${STORAGE_ACCOUNT} /pass:${STORAGE_KEY}\""
    echo "    New-PSDrive -Name Z -PSProvider FileSystem -Root \"\\\\${STORAGE_ACCOUNT}.file.core.windows.net\\${SHARE_NAME}\" -Persist"
    echo "} else {"
    echo "    Write-Error \"Unable to reach the Azure storage account via port 445.\""
    echo "}"
    echo ""
    echo "==============================================================================="
    echo ""
    echo "IMPORTANT: Store this storage key securely - it provides full access to the share."
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

main() {
    log "Starting Azure Files setup for Customer $CUSTOMER_NUMBER"
    
    configure_storage_security
    create_file_share
    create_folder_structure
    enable_soft_delete
    create_screen_recordings_container
    print_mount_instructions
}

main "$@"
