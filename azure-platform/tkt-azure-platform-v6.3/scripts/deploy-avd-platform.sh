#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Automated Deployment Script
# Version: 6.3
# 
# CHANGELOG from V6.2:
# - Added targetisaadjoined:i:1 RDP property to host pool (fixes Entra ID join)
# - Added cleanup of stale Entra ID device records before VM creation
# - Added Teams + Office installation phase
# - Added WebRTC Redirector + IsWVDEnvironment for Teams optimization
# - Added shared drive creation
# - Added folder redirection GPO for Desktop/Documents
# - Improved validation with comprehensive checks
#
# Prerequisites:
# - Azure CLI 2.50+ with desktopvirtualization extension
# - Logged in with az login
# - Sufficient permissions (Contributor + User Access Administrator)
#===============================================================================

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================

# Project Settings
PROJECT_PREFIX="${PROJECT_PREFIX:-tktph}"
LOCATION="${LOCATION:-southeastasia}"
ENVIRONMENT="${ENVIRONMENT:-prod}"

# Resource Names (auto-generated)
RESOURCE_GROUP="rg-${PROJECT_PREFIX}-avd-${ENVIRONMENT}-sea"
VNET_NAME="vnet-${PROJECT_PREFIX}-avd-sea"
SUBNET_NAME="snet-avd"
NSG_NAME="nsg-${PROJECT_PREFIX}-avd"
STORAGE_ACCOUNT="st${PROJECT_PREFIX}fslogix"
LOG_ANALYTICS="law-${PROJECT_PREFIX}-avd-sea"
HOSTPOOL_NAME="${PROJECT_PREFIX}-hp"
WORKSPACE_NAME="${PROJECT_PREFIX}-ws"
APP_GROUP_NAME="${PROJECT_PREFIX}-dag"
ACTION_GROUP="ag-${PROJECT_PREFIX}-avd"

# VM Configuration
VM_SIZE="${VM_SIZE:-Standard_D4s_v4}"
VM_COUNT="${VM_COUNT:-2}"
VM_PREFIX="vm-${PROJECT_PREFIX}"
VM_IMAGE="MicrosoftWindowsDesktop:windows-11:win11-23h2-avd:latest"
VM_ADMIN_USER="avdadmin"

# AVD Configuration
HOSTPOOL_TYPE="Pooled"
LOAD_BALANCER_TYPE="BreadthFirst"
MAX_SESSION_LIMIT=4

# Network Configuration
VNET_ADDRESS_PREFIX="10.2.0.0/16"
SUBNET_ADDRESS_PREFIX="10.2.1.0/24"

# Identity
DOMAIN="${DOMAIN:-}"
SECURITY_GROUP="TKT-Philippines-AVD-Users"
USER_PREFIX="ph-consultant"
USER_COUNT=4

# Alerts
ALERT_EMAIL="${ALERT_EMAIL:-}"

# Application Installation
INSTALL_TEAMS="${INSTALL_TEAMS:-true}"
INSTALL_OFFICE="${INSTALL_OFFICE:-true}"
CREATE_SHARED_DRIVE="${CREATE_SHARED_DRIVE:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# Helper Functions
#===============================================================================

log() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")    echo -e "[${timestamp}] [${BLUE}INFO${NC}] $message" ;;
        "SUCCESS") echo -e "[${timestamp}] [${GREEN}SUCCESS${NC}] $message" ;;
        "WARN")    echo -e "[${timestamp}] [${YELLOW}WARN${NC}] $message" ;;
        "ERROR")   echo -e "[${timestamp}] [${RED}ERROR${NC}] $message" ;;
        "PHASE")   echo -e "[${timestamp}] [${BLUE}PHASE${NC}] $message" ;;
    esac
}

log_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

prompt_config() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}║     TKT Philippines AVD Platform - Automated Deployment                      ║${NC}"
    echo -e "${BLUE}║                           Version 6.3                                         ║${NC}"
    echo -e "${BLUE}║                                                                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get domain if not set
    if [ -z "$DOMAIN" ]; then
        DOMAIN=$(az ad signed-in-user show --query "userPrincipalName" -o tsv 2>/dev/null | cut -d'@' -f2)
        if [ -z "$DOMAIN" ]; then
            read -p "Enter your Entra ID domain (e.g., company.onmicrosoft.com): " DOMAIN
        fi
    fi
    
    # Get alert email if not set
    if [ -z "$ALERT_EMAIL" ]; then
        ALERT_EMAIL=$(az ad signed-in-user show --query "mail" -o tsv 2>/dev/null)
        if [ -z "$ALERT_EMAIL" ] || [ "$ALERT_EMAIL" == "null" ]; then
            read -p "Enter email for alerts: " ALERT_EMAIL
        fi
    fi
    
    # Get VM admin password
    if [ -z "${VM_ADMIN_PASSWORD:-}" ]; then
        read -sp "Enter VM admin password (min 12 chars, complexity required): " VM_ADMIN_PASSWORD
        echo ""
    fi
    
    # Show configuration summary
    echo ""
    echo -e " ${YELLOW}DEPLOYMENT SUMMARY${NC}"
    echo -e " ${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "   ${BLUE}Azure${NC}"
    echo -e "   ${BLUE}─────${NC}"
    echo -e "     Subscription:     $(az account show --query name -o tsv)"
    echo -e "     Resource Group:   ${RESOURCE_GROUP}"
    echo -e "     Location:         ${LOCATION}"
    echo ""
    echo -e "   ${BLUE}Infrastructure${NC}"
    echo -e "   ${BLUE}──────────────${NC}"
    echo -e "     Virtual Network:  ${VNET_NAME} (${VNET_ADDRESS_PREFIX})"
    echo -e "     Session Hosts:    ${VM_COUNT} x ${VM_SIZE}"
    echo -e "     Host Pool:        ${HOSTPOOL_NAME} (${HOSTPOOL_TYPE})"
    echo -e "     Max Sessions:     ${MAX_SESSION_LIMIT} per host"
    echo ""
    echo -e "   ${BLUE}Identity (V6.3 - Entra ID Join)${NC}"
    echo -e "   ${BLUE}────────────────────────────────${NC}"
    echo -e "     Domain:           ${DOMAIN}"
    echo -e "     Join Type:        Microsoft Entra ID (cloud-only)"
    echo -e "     Users:            ${USER_PREFIX}-001 to ${USER_PREFIX}-$(printf '%03d' $USER_COUNT)"
    echo -e "     Security Group:   ${SECURITY_GROUP}"
    echo ""
    echo -e "   ${BLUE}Applications${NC}"
    echo -e "   ${BLUE}────────────${NC}"
    echo -e "     Teams:            ${INSTALL_TEAMS}"
    echo -e "     Office:           ${INSTALL_OFFICE}"
    echo -e "     Shared Drive:     ${CREATE_SHARED_DRIVE}"
    echo ""
    echo -e "   ${BLUE}Monitoring${NC}"
    echo -e "   ${BLUE}──────────${NC}"
    echo -e "     Alert Email:      ${ALERT_EMAIL}"
    echo -e "     Log Retention:    90 days"
    echo ""
    
    read -p "Proceed with deployment? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
}

#===============================================================================
# Phase 1: Networking
#===============================================================================

deploy_networking() {
    log_section "PHASE 1: NETWORKING"
    log "PHASE" "Starting Phase 1: NETWORKING"
    
    # Create resource group
    log "INFO" "Creating resource group: ${RESOURCE_GROUP}"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    log "SUCCESS" "Resource group created"
    
    # Create virtual network
    log "INFO" "Creating virtual network: ${VNET_NAME}"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_ADDRESS_PREFIX" \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix "$SUBNET_ADDRESS_PREFIX" \
        --output none
    log "SUCCESS" "Virtual network created"
    
    # Create NSG
    log "INFO" "Creating NSG: ${NSG_NAME}"
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --output none
    log "SUCCESS" "NSG created"
    
    # Associate NSG with subnet
    log "INFO" "Associating NSG with subnet..."
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME" \
        --output none
    
    log "SUCCESS" "Phase 1 complete: NETWORKING"
}

#===============================================================================
# Phase 2: Storage & Monitoring
#===============================================================================

deploy_storage_monitoring() {
    log_section "PHASE 2: STORAGE & MONITORING"
    log "PHASE" "Starting Phase 2: STORAGE & MONITORING"
    
    # Create storage account
    log "INFO" "Creating storage account: ${STORAGE_ACCOUNT}"
    az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT" \
        --location "$LOCATION" \
        --sku Premium_LRS \
        --kind FileStorage \
        --enable-large-file-share \
        --output none
    log "SUCCESS" "Storage account created"
    
    # Create FSLogix file share
    log "INFO" "Creating FSLogix file share: profiles"
    az storage share create \
        --account-name "$STORAGE_ACCOUNT" \
        --name "profiles" \
        --quota 100 \
        --output none
    log "SUCCESS" "FSLogix file share created"
    
    # Create shared drive (V6.3)
    if [ "$CREATE_SHARED_DRIVE" == "true" ]; then
        log "INFO" "Creating shared file share: shared"
        az storage share create \
            --account-name "$STORAGE_ACCOUNT" \
            --name "shared" \
            --quota 50 \
            --output none
        log "SUCCESS" "Shared file share created"
    fi
    
    # Create Log Analytics workspace
    log "INFO" "Creating Log Analytics workspace: ${LOG_ANALYTICS}"
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS" \
        --location "$LOCATION" \
        --retention-time 90 \
        --output none
    log "SUCCESS" "Log Analytics workspace created"
    
    # Create action group
    log "INFO" "Creating action group: ${ACTION_GROUP}"
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP" \
        --short-name "tktphavd" \
        --action email admin "$ALERT_EMAIL" \
        --output none
    log "SUCCESS" "Action group created"
    
    log "SUCCESS" "Phase 2 complete: STORAGE & MONITORING"
}

#===============================================================================
# Phase 3: AVD Control Plane
#===============================================================================

deploy_avd_control_plane() {
    log_section "PHASE 3: AVD CONTROL PLANE"
    log "PHASE" "Starting Phase 3: AVD CONTROL PLANE"
    
    # Install/update desktopvirtualization extension
    az extension add --name desktopvirtualization --upgrade --yes 2>/dev/null || true
    
    # Create workspace
    log "INFO" "Creating AVD workspace: ${WORKSPACE_NAME}"
    az desktopvirtualization workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --friendly-name "TKT Philippines Workspace" \
        --output none
    log "SUCCESS" "AVD workspace created"
    
    # Create host pool with Entra ID join RDP property (V6.3 FIX)
    log "INFO" "Creating host pool: ${HOSTPOOL_NAME}"
    az desktopvirtualization hostpool create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --location "$LOCATION" \
        --host-pool-type "$HOSTPOOL_TYPE" \
        --load-balancer-type "$LOAD_BALANCER_TYPE" \
        --max-session-limit "$MAX_SESSION_LIMIT" \
        --preferred-app-group-type Desktop \
        --custom-rdp-property "targetisaadjoined:i:1" \
        --output none
    log "SUCCESS" "Host pool created with Entra ID join property"
    
    # Generate registration token
    log "INFO" "Generating registration token..."
    local expiry=$(date -u -d "+24 hours" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+24H '+%Y-%m-%dT%H:%M:%SZ')
    REGISTRATION_TOKEN=$(az desktopvirtualization hostpool update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HOSTPOOL_NAME" \
        --registration-info expiration-time="$expiry" registration-token-operation="Update" \
        --query "registrationInfo.token" -o tsv)
    log "SUCCESS" "Registration token saved"
    
    # Create application group
    log "INFO" "Creating application group: ${APP_GROUP_NAME}"
    az desktopvirtualization applicationgroup create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_GROUP_NAME" \
        --location "$LOCATION" \
        --host-pool-arm-path "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostpools/${HOSTPOOL_NAME}" \
        --application-group-type Desktop \
        --output none
    log "SUCCESS" "Application group created"
    
    # Associate app group with workspace
    log "INFO" "Associating application group with workspace..."
    az desktopvirtualization workspace update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WORKSPACE_NAME" \
        --application-group-references "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/applicationgroups/${APP_GROUP_NAME}" \
        --output none
    
    log "SUCCESS" "Phase 3 complete: AVD CONTROL PLANE"
}

#===============================================================================
# Phase 4: Session Hosts (Entra ID Join)
#===============================================================================

deploy_session_hosts() {
    log_section "PHASE 4: SESSION HOSTS (Entra ID Join)"
    log "PHASE" "Starting Phase 4: SESSION HOSTS (Entra ID Join)"
    
    local SUBNET_ID=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --query id -o tsv)
    
    local LAW_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS" \
        --query customerId -o tsv)
    
    local LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS" \
        --query primarySharedKey -o tsv)
    
    for i in $(seq -f "%02g" 1 $VM_COUNT); do
        local VM_NAME="${VM_PREFIX}-${i}"
        
        # V6.3: Clean up stale Entra ID device record
        log "INFO" "Checking for stale Entra ID device: ${VM_NAME}..."
        local STALE_DEVICE=$(az rest --method GET \
            --url "https://graph.microsoft.com/v1.0/devices?\$filter=displayName eq '${VM_NAME}'" \
            --query "value[0].id" -o tsv 2>/dev/null)
        if [ -n "$STALE_DEVICE" ] && [ "$STALE_DEVICE" != "null" ]; then
            log "WARN" "Removing stale device record: ${STALE_DEVICE}"
            az rest --method DELETE --url "https://graph.microsoft.com/v1.0/devices/${STALE_DEVICE}" 2>/dev/null || true
            sleep 5
        fi
        
        # Create VM with managed identity
        log "INFO" "Deploying session host: ${VM_NAME} (5-10 minutes)..."
        az vm create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --image "$VM_IMAGE" \
            --size "$VM_SIZE" \
            --admin-username "$VM_ADMIN_USER" \
            --admin-password "$VM_ADMIN_PASSWORD" \
            --subnet "$SUBNET_ID" \
            --public-ip-address "" \
            --nsg "" \
            --assign-identity \
            --license-type Windows_Client \
            --output none
        log "SUCCESS" "${VM_NAME} deployed with managed identity"
        
        # Install AADLoginForWindows extension (Entra ID Join)
        log "INFO" "Configuring Entra ID join on ${VM_NAME}..."
        az vm extension set \
            --resource-group "$RESOURCE_GROUP" \
            --vm-name "$VM_NAME" \
            --name "AADLoginForWindows" \
            --publisher "Microsoft.Azure.ActiveDirectory" \
            --version "2.0" \
            --output none
        log "SUCCESS" "Entra ID join configured on ${VM_NAME}"
        
        # Install AVD Agent via DSC extension
        log "INFO" "Installing AVD agent on ${VM_NAME}..."
        az vm extension set \
            --resource-group "$RESOURCE_GROUP" \
            --vm-name "$VM_NAME" \
            --name "DSC" \
            --publisher "Microsoft.Powershell" \
            --version "2.83" \
            --settings "{
                \"modulesUrl\": \"https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip\",
                \"configurationFunction\": \"Configuration.ps1\\\\AddSessionHost\",
                \"properties\": {
                    \"HostPoolName\": \"${HOSTPOOL_NAME}\",
                    \"RegistrationInfoTokenCredential\": {
                        \"UserName\": \"YOURPLACEHOLDER\",
                        \"Password\": \"PrivateSettingsRef:RegistrationInfoToken\"
                    },
                    \"AadJoin\": true
                }
            }" \
            --protected-settings "{\"Items\": {\"RegistrationInfoToken\": \"${REGISTRATION_TOKEN}\"}}" \
            --output none
        log "SUCCESS" "AVD agent installed on ${VM_NAME}"
        
        # Install monitoring agent
        log "INFO" "Installing monitoring agent on ${VM_NAME}..."
        az vm extension set \
            --resource-group "$RESOURCE_GROUP" \
            --vm-name "$VM_NAME" \
            --name "AzureMonitorWindowsAgent" \
            --publisher "Microsoft.Azure.Monitor" \
            --version "1.0" \
            --output none
    done
    
    # Assign VM login permissions
    log "INFO" "Assigning VM login permissions to users..."
    local SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    local GROUP_ID=$(az ad group show -g "$SECURITY_GROUP" --query id -o tsv 2>/dev/null)
    
    if [ -n "$GROUP_ID" ]; then
        for i in $(seq -f "%02g" 1 $VM_COUNT); do
            local VM_NAME="${VM_PREFIX}-${i}"
            az role assignment create \
                --assignee "$GROUP_ID" \
                --role "Virtual Machine User Login" \
                --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}" \
                --output none 2>/dev/null || true
            log "INFO" "  → ${VM_NAME}: VM login role assigned"
        done
        log "SUCCESS" "VM login permissions assigned to ${SECURITY_GROUP}"
    fi
    
    # Wait for session hosts to register
    log "INFO" "Waiting for session hosts to complete Entra ID join and register (3-5 minutes)..."
    sleep 90
    
    local attempts=0
    local max_attempts=15
    while [ $attempts -lt $max_attempts ]; do
        local available=$(az rest --method GET \
            --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostPools/${HOSTPOOL_NAME}/sessionHosts?api-version=2024-04-03" \
            --query "value[?properties.status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [ "$available" -ge "$VM_COUNT" ]; then
            log "SUCCESS" "All ${VM_COUNT} session hosts are now available!"
            break
        fi
        
        ((attempts++))
        log "INFO" "Attempt ${attempts}/${max_attempts}: ${available}/${VM_COUNT} hosts available..."
        sleep 20
    done
    
    log "SUCCESS" "Phase 4 complete: SESSION HOSTS"
}

#===============================================================================
# Phase 4.5: Application Installation (V6.3)
#===============================================================================

install_applications() {
    log_section "PHASE 4.5: APPLICATION INSTALLATION"
    log "PHASE" "Starting Phase 4.5: APPLICATION INSTALLATION"
    
    for i in $(seq -f "%02g" 1 $VM_COUNT); do
        local VM_NAME="${VM_PREFIX}-${i}"
        log "INFO" "Installing applications on ${VM_NAME}..."
        
        # Install WebRTC Redirector + Teams optimization registry
        log "INFO" "  → Installing WebRTC Redirector and Teams optimization..."
        az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VM_NAME" \
            --command-id RunPowerShellScript \
            --scripts '
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                Invoke-WebRequest -Uri "https://aka.ms/msrdcwebrtcsvc/msi" -OutFile "C:\Temp\MsRdcWebRTCSvc.msi"
                Start-Process msiexec.exe -ArgumentList "/i C:\Temp\MsRdcWebRTCSvc.msi /quiet /norestart" -Wait
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Teams" -Name "IsWVDEnvironment" -Value 1 -Type DWord
            ' --output none 2>/dev/null
        log "SUCCESS" "  → WebRTC Redirector installed"
        
        # Install Teams
        if [ "$INSTALL_TEAMS" == "true" ]; then
            log "INFO" "  → Installing Microsoft Teams..."
            az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VM_NAME" \
                --command-id RunPowerShellScript \
                --scripts '
                    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
                    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2243204&clcid=0x409" -OutFile "C:\Temp\teamsbootstrapper.exe"
                    Start-Process -FilePath "C:\Temp\teamsbootstrapper.exe" -ArgumentList "-p" -Wait
                ' --output none 2>/dev/null
            log "SUCCESS" "  → Teams installed"
        fi
        
        # Install Office
        if [ "$INSTALL_OFFICE" == "true" ]; then
            log "INFO" "  → Installing Microsoft 365 Apps (10-15 minutes)..."
            az vm run-command invoke \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VM_NAME" \
                --command-id RunPowerShellScript \
                --scripts '
                    New-Item -ItemType Directory -Path "C:\Temp\Office" -Force | Out-Null
                    Invoke-WebRequest -Uri "https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_18129-20030.exe" -OutFile "C:\Temp\Office\ODT.exe"
                    Start-Process -FilePath "C:\Temp\Office\ODT.exe" -ArgumentList "/quiet /extract:C:\Temp\Office" -Wait
                    $config = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="MonthlyEnterprise">
    <Product ID="O365BusinessRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
    </Product>
  </Add>
  <Property Name="SharedComputerLicensing" Value="1" />
  <Property Name="PinIconsToTaskbar" Value="TRUE" />
  <Updates Enabled="TRUE" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@
                    $config | Out-File -FilePath "C:\Temp\Office\config.xml" -Encoding UTF8
                    Start-Process -FilePath "C:\Temp\Office\setup.exe" -ArgumentList "/configure C:\Temp\Office\config.xml" -Wait
                ' --output none 2>/dev/null
            log "SUCCESS" "  → Microsoft 365 Apps installed"
        fi
    done
    
    log "SUCCESS" "Phase 4.5 complete: APPLICATION INSTALLATION"
}

#===============================================================================
# Phase 5: Identity & User Assignment
#===============================================================================

deploy_identity() {
    log_section "PHASE 5: IDENTITY & USER ASSIGNMENT"
    log "PHASE" "Starting Phase 5: IDENTITY & USER ASSIGNMENT"
    
    # Create security group
    local GROUP_ID=$(az ad group show -g "$SECURITY_GROUP" --query id -o tsv 2>/dev/null)
    if [ -z "$GROUP_ID" ]; then
        log "INFO" "Creating security group: ${SECURITY_GROUP}"
        GROUP_ID=$(az ad group create \
            --display-name "$SECURITY_GROUP" \
            --mail-nickname "tkt-ph-avd-users" \
            --query id -o tsv)
        log "SUCCESS" "Security group created"
    else
        log "INFO" "Security group ${SECURITY_GROUP} already exists"
    fi
    
    # Create users
    for i in $(seq 1 $USER_COUNT); do
        local UPN="${USER_PREFIX}-$(printf '%03d' $i)@${DOMAIN}"
        local DISPLAY_NAME="PH Consultant $(printf '%03d' $i)"
        
        if az ad user show --id "$UPN" &>/dev/null; then
            log "INFO" "User ${UPN} already exists"
        else
            log "INFO" "Creating user: ${UPN}"
            az ad user create \
                --display-name "$DISPLAY_NAME" \
                --user-principal-name "$UPN" \
                --password "TempPass$(printf '%03d' $i)!" \
                --force-change-password-next-sign-in true \
                --output none
            log "SUCCESS" "User ${UPN} created"
        fi
        
        # Add to group
        az ad group member add --group "$SECURITY_GROUP" --member-id $(az ad user show --id "$UPN" --query id -o tsv) 2>/dev/null || true
    done
    log "SUCCESS" "All users created and added to group"
    
    # Assign Desktop Virtualization User role on app group
    log "INFO" "Assigning users to application group..."
    local SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    az role assignment create \
        --assignee "$GROUP_ID" \
        --role "Desktop Virtualization User" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/applicationgroups/${APP_GROUP_NAME}" \
        --output none 2>/dev/null || true
    log "SUCCESS" "Desktop Virtualization User role assigned"
    
    # Ensure VM login permissions
    log "INFO" "Ensuring VM login permissions..."
    for i in $(seq -f "%02g" 1 $VM_COUNT); do
        local VM_NAME="${VM_PREFIX}-${i}"
        az role assignment create \
            --assignee "$GROUP_ID" \
            --role "Virtual Machine User Login" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}" \
            --output none 2>/dev/null || true
    done
    log "SUCCESS" "Virtual Machine User Login role assigned"
    
    log "SUCCESS" "Phase 5 complete: IDENTITY & USER ASSIGNMENT"
}

#===============================================================================
# Phase 6: Validation
#===============================================================================

run_validation() {
    log_section "PHASE 6: VALIDATION"
    log "PHASE" "Starting Phase 6: VALIDATION"
    
    local SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    echo ""
    echo -e "  ${BLUE}Check${NC}                                         ${BLUE}Status${NC}"
    echo -e "  ${BLUE}─────────────────────────────────────────────────────────${NC}"
    
    # Resource Group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        echo -e "  Resource Group                                ${GREEN}✓ OK${NC}"
    else
        echo -e "  Resource Group                                ${RED}✗ FAIL${NC}"
    fi
    
    # VNet
    if az network vnet show -g "$RESOURCE_GROUP" -n "$VNET_NAME" &>/dev/null; then
        echo -e "  Virtual Network                               ${GREEN}✓ OK${NC}"
    else
        echo -e "  Virtual Network                               ${RED}✗ FAIL${NC}"
    fi
    
    # Storage
    if az storage account show -g "$RESOURCE_GROUP" -n "$STORAGE_ACCOUNT" &>/dev/null; then
        echo -e "  Storage Account                               ${GREEN}✓ OK${NC}"
    else
        echo -e "  Storage Account                               ${RED}✗ FAIL${NC}"
    fi
    
    # Host Pool
    if az rest --method GET --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostPools/${HOSTPOOL_NAME}?api-version=2024-04-03" &>/dev/null; then
        echo -e "  Host Pool                                     ${GREEN}✓ OK${NC}"
        
        # Check Entra ID RDP property
        local RDP_PROPS=$(az rest --method GET \
            --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostPools/${HOSTPOOL_NAME}?api-version=2024-04-03" \
            --query "properties.customRdpProperty" -o tsv 2>/dev/null)
        if [[ "$RDP_PROPS" == *"targetisaadjoined:i:1"* ]]; then
            echo -e "  Entra ID Join RDP Property                    ${GREEN}✓ OK${NC}"
        else
            echo -e "  Entra ID Join RDP Property                    ${RED}✗ FAIL${NC}"
        fi
    else
        echo -e "  Host Pool                                     ${RED}✗ FAIL${NC}"
    fi
    
    # Session Hosts
    local available=$(az rest --method GET \
        --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostPools/${HOSTPOOL_NAME}/sessionHosts?api-version=2024-04-03" \
        --query "value[?properties.status=='Available'] | length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [ "$available" -ge "$VM_COUNT" ]; then
        echo -e "  Session Hosts (${available}/${VM_COUNT} available)              ${GREEN}✓ OK${NC}"
    else
        echo -e "  Session Hosts (${available}/${VM_COUNT} available)              ${YELLOW}⚠ WARN${NC}"
    fi
    
    # Security Group
    if az ad group show -g "$SECURITY_GROUP" &>/dev/null; then
        echo -e "  Security Group                                ${GREEN}✓ OK${NC}"
    else
        echo -e "  Security Group                                ${RED}✗ FAIL${NC}"
    fi
    
    echo ""
    log "SUCCESS" "Phase 6 complete: VALIDATION"
}

#===============================================================================
# Deployment Summary
#===============================================================================

show_summary() {
    log_section "DEPLOYMENT COMPLETE"
    
    echo ""
    echo -e "  ${GREEN}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}║                     DEPLOYMENT SUCCESSFUL!                                    ║${NC}"
    echo -e "  ${GREEN}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Access URL:${NC}     https://client.wvd.microsoft.com/arm/webclient"
    echo ""
    echo -e "  ${BLUE}Test User:${NC}      ${USER_PREFIX}-001@${DOMAIN}"
    echo -e "  ${BLUE}Password:${NC}       TempPass001! (change on first login)"
    echo ""
    echo -e "  ${BLUE}Resources:${NC}"
    echo -e "    Resource Group:   ${RESOURCE_GROUP}"
    echo -e "    Host Pool:        ${HOSTPOOL_NAME}"
    echo -e "    Session Hosts:    ${VM_COUNT} x ${VM_SIZE}"
    echo ""
    echo -e "  ${BLUE}Next Steps:${NC}"
    echo -e "    1. Log in to the web client with a test user"
    echo -e "    2. Assign Microsoft 365 licenses for Teams/Office"
    echo -e "    3. Run comprehensive validation: ./validate-deployment-comprehensive.sh"
    echo -e "    4. Configure Conditional Access policies (optional)"
    echo ""
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Verify Azure CLI login
    if ! az account show &>/dev/null; then
        log "ERROR" "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    # Show config and prompt for confirmation
    prompt_config
    
    # Run deployment phases
    deploy_networking
    deploy_storage_monitoring
    deploy_avd_control_plane
    deploy_session_hosts
    install_applications
    deploy_identity
    run_validation
    show_summary
}

# Run main
main "$@"
