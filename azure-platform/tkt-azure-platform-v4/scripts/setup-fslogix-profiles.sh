#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - FSLogix Profile Configuration
# Version: 4.0
# Date: 2026-02-12
#
# This script configures FSLogix profile containers on Azure Files and
# installs/configures FSLogix on session hosts.
#
# Prerequisites:
#   - Azure CLI authenticated with Contributor role
#   - Storage account with Premium FileStorage created
#   - Session hosts deployed and running
#   - FSLogix share created (profiles)
#
# Usage:
#   ./setup-fslogix-profiles.sh --resource-group <rg> --storage-account <sa> \
#       --vm-prefix <prefix> --vm-count <count> [--dry-run]
#
# Environment Variables (alternative to flags):
#   RESOURCE_GROUP, STORAGE_ACCOUNT, VM_PREFIX, VM_COUNT
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${LOG_FILE:-/tmp/fslogix-config-$(date +%Y%m%d-%H%M%S).log}"

# Defaults
DRY_RUN=false
SHARE_NAME="profiles"
FSLOGIX_DOWNLOAD_URL="https://aka.ms/fslogix_download"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#-------------------------------------------------------------------------------
# Logging Functions
#-------------------------------------------------------------------------------

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        SUCCESS) echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[$timestamp] [ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#-------------------------------------------------------------------------------
# Usage
#-------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Configure FSLogix profile containers for AVD session hosts.

Options:
    --resource-group <name>    Azure resource group name
    --storage-account <name>   Storage account name for profiles
    --vm-prefix <prefix>       Session host VM name prefix
    --vm-count <count>         Number of session hosts (default: 2)
    --share-name <name>        File share name (default: profiles)
    --dry-run                  Show what would be done without making changes
    -h, --help                 Show this help message

Environment Variables:
    RESOURCE_GROUP            Resource group name
    STORAGE_ACCOUNT           Storage account name
    VM_PREFIX                 VM name prefix
    VM_COUNT                  Number of VMs

Examples:
    $SCRIPT_NAME --resource-group rg-tktph-avd --storage-account sttktphfslogix \\
        --vm-prefix tktph-sh --vm-count 2

    RESOURCE_GROUP=rg-tktph-avd STORAGE_ACCOUNT=sttktphfslogix \\
        VM_PREFIX=tktph-sh VM_COUNT=2 $SCRIPT_NAME
EOF
    exit 0
}

#-------------------------------------------------------------------------------
# Parse Arguments
#-------------------------------------------------------------------------------

parse_args() {
    RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    VM_PREFIX="${VM_PREFIX:-}"
    VM_COUNT="${VM_COUNT:-2}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
            --storage-account) STORAGE_ACCOUNT="$2"; shift 2 ;;
            --vm-prefix) VM_PREFIX="$2"; shift 2 ;;
            --vm-count) VM_COUNT="$2"; shift 2 ;;
            --share-name) SHARE_NAME="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage ;;
            *) log ERROR "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "Resource group is required (--resource-group or RESOURCE_GROUP)"
        exit 1
    fi
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        log ERROR "Storage account is required (--storage-account or STORAGE_ACCOUNT)"
        exit 1
    fi
    if [[ -z "$VM_PREFIX" ]]; then
        log ERROR "VM prefix is required (--vm-prefix or VM_PREFIX)"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Validation Functions
#-------------------------------------------------------------------------------

validate_storage_account() {
    log INFO "Validating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "Storage account '$STORAGE_ACCOUNT' not found in resource group '$RESOURCE_GROUP'"
        return 1
    fi
    
    # Check storage account kind
    local kind=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
        --query "kind" -o tsv)
    
    if [[ "$kind" != "FileStorage" ]]; then
        log WARN "Storage account kind is '$kind'. Premium FileStorage recommended for FSLogix."
    else
        log SUCCESS "Storage account is Premium FileStorage (optimal for FSLogix)"
    fi
    
    # Check if share exists
    local storage_key=$(az storage account keys list --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" --query "[0].value" -o tsv)
    
    if az storage share show --name "$SHARE_NAME" --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" &>/dev/null; then
        log SUCCESS "File share '$SHARE_NAME' exists"
    else
        log ERROR "File share '$SHARE_NAME' not found. Create it first."
        return 1
    fi
    
    return 0
}

validate_session_hosts() {
    log INFO "Validating session hosts..."
    
    local valid_count=0
    for i in $(seq 1 "$VM_COUNT"); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        
        if az vm show --name "$vm_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            local power_state=$(az vm get-instance-view --name "$vm_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv)
            
            if [[ "$power_state" == "VM running" ]]; then
                log SUCCESS "Session host '$vm_name' is running"
                ((valid_count++))
            else
                log WARN "Session host '$vm_name' is not running (state: $power_state)"
            fi
        else
            log WARN "Session host '$vm_name' not found"
        fi
    done
    
    if [[ $valid_count -eq 0 ]]; then
        log ERROR "No running session hosts found"
        return 1
    fi
    
    log INFO "Found $valid_count running session host(s)"
    return 0
}

#-------------------------------------------------------------------------------
# FSLogix Configuration Script (PowerShell)
#-------------------------------------------------------------------------------

generate_fslogix_script() {
    local storage_account="$1"
    local share_name="$2"
    
    cat << 'PWSH_SCRIPT'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures FSLogix Profile Containers on AVD session host.
.DESCRIPTION
    - Downloads and installs FSLogix agent
    - Configures registry settings for profile containers
    - Sets up VHD location to Azure Files
    - Configures exclusions and optimizations
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ShareName,
    
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\WindowsAzure\Logs\FSLogix-Config.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
}

try {
    Write-Log "Starting FSLogix configuration"
    Write-Log "Storage Account: $StorageAccountName"
    Write-Log "Share Name: $ShareName"
    
    $ProfilePath = "\\$StorageAccountName.file.core.windows.net\$ShareName"
    Write-Log "Profile Path: $ProfilePath"
    
    # Check if FSLogix is already installed
    $fslogixPath = "C:\Program Files\FSLogix\Apps\frx.exe"
    if (Test-Path $fslogixPath) {
        Write-Log "FSLogix is already installed"
        $version = (Get-Item $fslogixPath).VersionInfo.FileVersion
        Write-Log "FSLogix version: $version"
    } else {
        Write-Log "Downloading FSLogix..."
        
        if (-not $DryRun) {
            $downloadPath = "C:\Temp\FSLogix.zip"
            $extractPath = "C:\Temp\FSLogix"
            
            New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
            
            # Download FSLogix
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri "https://aka.ms/fslogix_download" -OutFile $downloadPath
            
            Write-Log "Extracting FSLogix..."
            Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
            
            Write-Log "Installing FSLogix..."
            $installer = Get-ChildItem -Path $extractPath -Filter "FSLogixAppsSetup.exe" -Recurse | 
                Where-Object { $_.FullName -match "x64" } | Select-Object -First 1
            
            if ($installer) {
                Start-Process -FilePath $installer.FullName -ArgumentList "/install /quiet /norestart" -Wait
                Write-Log "FSLogix installed successfully"
            } else {
                throw "FSLogix installer not found"
            }
            
            # Cleanup
            Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "[DRY-RUN] Would download and install FSLogix"
        }
    }
    
    # Configure FSLogix Registry Settings
    Write-Log "Configuring FSLogix registry settings..."
    
    $registrySettings = @{
        # Profile Container Settings
        "HKLM:\SOFTWARE\FSLogix\Profiles" = @{
            "Enabled" = 1
            "VHDLocations" = $ProfilePath
            "DeleteLocalProfileWhenVHDShouldApply" = 1
            "FlipFlopProfileDirectoryName" = 1
            "LockedRetryCount" = 3
            "LockedRetryInterval" = 15
            "ProfileType" = 0  # Normal profile
            "ReAttachRetryCount" = 3
            "ReAttachIntervalSeconds" = 15
            "SizeInMBs" = 30000  # 30GB max profile size
            "VolumeType" = "VHDX"
            "IsDynamic" = 1
            "KeepLocalDir" = 0
            "RoamSearch" = 2  # Single-user search
            "PreventLoginWithFailure" = 0
            "PreventLoginWithTempProfile" = 0
            "AccessNetworkAsComputerObject" = 1
        }
        # Office Container Settings (optional, for large Outlook caches)
        "HKLM:\SOFTWARE\Policies\FSLogix\ODFC" = @{
            "Enabled" = 1
            "VHDLocations" = $ProfilePath
            "IncludeOfficeActivation" = 1
            "IncludeOneDrive" = 1
            "IncludeOutlook" = 1
            "IncludeOutlookPersonalization" = 1
            "IncludeSharepoint" = 1
            "IncludeTeams" = 1
            "VolumeType" = "VHDX"
        }
    }
    
    foreach ($path in $registrySettings.Keys) {
        if (-not $DryRun) {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
                Write-Log "Created registry path: $path"
            }
            
            foreach ($name in $registrySettings[$path].Keys) {
                $value = $registrySettings[$path][$name]
                Set-ItemProperty -Path $path -Name $name -Value $value
                Write-Log "Set $path\$name = $value"
            }
        } else {
            Write-Log "[DRY-RUN] Would configure registry: $path"
        }
    }
    
    # Configure local group membership for FSLogix
    Write-Log "Configuring FSLogix local groups..."
    
    $groups = @(
        @{Name = "FSLogix Profile Exclude List"; Members = @("Administrator")},
        @{Name = "FSLogix ODFC Exclude List"; Members = @("Administrator")}
    )
    
    foreach ($group in $groups) {
        try {
            $localGroup = [ADSI]"WinNT://./$($group.Name),group"
            foreach ($member in $group.Members) {
                try {
                    $localGroup.Add("WinNT://./$member,user")
                    Write-Log "Added '$member' to '$($group.Name)'"
                } catch {
                    if ($_.Exception.Message -match "already a member") {
                        Write-Log "'$member' is already a member of '$($group.Name)'"
                    } else {
                        Write-Log "Could not add '$member' to '$($group.Name)': $_" "WARN"
                    }
                }
            }
        } catch {
            Write-Log "Group '$($group.Name)' may not exist yet. Will be created on first login." "WARN"
        }
    }
    
    # Test connectivity to file share
    Write-Log "Testing connectivity to profile share..."
    
    $testPath = "\\$StorageAccountName.file.core.windows.net\$ShareName"
    $testResult = Test-NetConnection -ComputerName "$StorageAccountName.file.core.windows.net" -Port 445
    
    if ($testResult.TcpTestSucceeded) {
        Write-Log "Successfully connected to storage account on port 445" "SUCCESS"
    } else {
        Write-Log "Cannot connect to storage account on port 445. Check NSG rules." "ERROR"
    }
    
    # Verify FSLogix service
    if (-not $DryRun) {
        $service = Get-Service -Name "frxsvc" -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Running") {
                Start-Service -Name "frxsvc"
                Write-Log "Started FSLogix service"
            } else {
                Write-Log "FSLogix service is running"
            }
        } else {
            Write-Log "FSLogix service not found. May require reboot." "WARN"
        }
    }
    
    Write-Log "FSLogix configuration completed successfully" "SUCCESS"
    
    # Output summary
    Write-Output @"

=== FSLogix Configuration Summary ===
Profile Container: Enabled
VHD Location: $ProfilePath
Volume Type: VHDX (Dynamic)
Max Size: 30GB
Office Container: Enabled
Search Roaming: Enabled

Next Steps:
1. Reboot the session host to apply all settings
2. Test user login and verify profile creation
3. Check C:\WindowsAzure\Logs\FSLogix-Config.log for details

"@
    
} catch {
    Write-Log "FSLogix configuration failed: $_" "ERROR"
    throw
}
PWSH_SCRIPT
}

#-------------------------------------------------------------------------------
# Apply FSLogix Configuration
#-------------------------------------------------------------------------------

configure_fslogix_on_host() {
    local vm_name="$1"
    
    log INFO "Configuring FSLogix on '$vm_name'..."
    
    # Generate PowerShell script content
    local ps_script=$(generate_fslogix_script "$STORAGE_ACCOUNT" "$SHARE_NAME")
    
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Would execute FSLogix configuration on $vm_name"
        return 0
    fi
    
    # Create temporary script file
    local temp_script="/tmp/fslogix-config-$$-$(date +%s).ps1"
    echo "$ps_script" > "$temp_script"
    
    # Execute via az vm run-command
    log INFO "Executing FSLogix configuration script on $vm_name..."
    
    local result=$(az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --command-id RunPowerShellScript \
        --scripts @"$temp_script" \
        --parameters "StorageAccountName=$STORAGE_ACCOUNT" "ShareName=$SHARE_NAME" \
        --query "value[0].message" -o tsv 2>&1)
    
    local exit_code=$?
    rm -f "$temp_script"
    
    if [[ $exit_code -eq 0 ]]; then
        log SUCCESS "FSLogix configured successfully on $vm_name"
        echo "$result" >> "$LOG_FILE"
        return 0
    else
        log ERROR "FSLogix configuration failed on $vm_name"
        echo "$result" >> "$LOG_FILE"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Configure Storage RBAC
#-------------------------------------------------------------------------------

configure_storage_rbac() {
    log INFO "Configuring storage account RBAC for AVD users..."
    
    # Get storage account resource ID
    local storage_id=$(az storage account show --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
    
    # Get AVD users group (created by entra-id-automation script)
    local group_id=$(az ad group show --group "TKT-Philippines-AVD-Users" \
        --query "id" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$group_id" ]]; then
        log WARN "AVD users group not found. RBAC assignment skipped."
        log WARN "Users will need storage permissions configured manually or via identity script."
        return 0
    fi
    
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Would assign 'Storage File Data SMB Share Contributor' to group"
        return 0
    fi
    
    # Assign Storage File Data SMB Share Contributor role
    log INFO "Assigning 'Storage File Data SMB Share Contributor' role..."
    
    az role assignment create \
        --assignee "$group_id" \
        --role "Storage File Data SMB Share Contributor" \
        --scope "$storage_id" 2>/dev/null || {
            log WARN "Role assignment may already exist or require different permissions"
        }
    
    log SUCCESS "Storage RBAC configured"
}

#-------------------------------------------------------------------------------
# Validation
#-------------------------------------------------------------------------------

validate_fslogix_setup() {
    log INFO "Validating FSLogix setup..."
    
    local validation_results=()
    local all_passed=true
    
    # Check storage connectivity from each host
    for i in $(seq 1 "$VM_COUNT"); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        
        if ! az vm show --name "$vm_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            continue
        fi
        
        log INFO "Testing FSLogix on $vm_name..."
        
        local test_script='
            $result = @{
                FSLogixInstalled = Test-Path "C:\Program Files\FSLogix\Apps\frx.exe"
                ProfilesEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled -eq 1
                ServiceRunning = (Get-Service -Name "frxsvc" -ErrorAction SilentlyContinue).Status -eq "Running"
            }
            $result | ConvertTo-Json
        '
        
        if $DRY_RUN; then
            log INFO "[DRY-RUN] Would validate FSLogix on $vm_name"
            continue
        fi
        
        local result=$(az vm run-command invoke \
            --resource-group "$RESOURCE_GROUP" \
            --name "$vm_name" \
            --command-id RunPowerShellScript \
            --scripts "$test_script" \
            --query "value[0].message" -o tsv 2>&1)
        
        if echo "$result" | grep -q '"FSLogixInstalled": true'; then
            log SUCCESS "$vm_name: FSLogix installed"
        else
            log ERROR "$vm_name: FSLogix NOT installed"
            all_passed=false
        fi
        
        if echo "$result" | grep -q '"ProfilesEnabled": true'; then
            log SUCCESS "$vm_name: Profile containers enabled"
        else
            log WARN "$vm_name: Profile containers may need reboot"
        fi
    done
    
    if $all_passed; then
        log SUCCESS "FSLogix validation completed successfully"
        return 0
    else
        log WARN "Some validations failed. Check logs for details."
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    echo ""
    echo "============================================================"
    echo "  TKT Philippines AVD - FSLogix Profile Configuration"
    echo "============================================================"
    echo ""
    
    parse_args "$@"
    
    log INFO "Starting FSLogix configuration"
    log INFO "Log file: $LOG_FILE"
    
    if $DRY_RUN; then
        log WARN "DRY-RUN MODE - No changes will be made"
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Resource Group:   $RESOURCE_GROUP"
    echo "  Storage Account:  $STORAGE_ACCOUNT"
    echo "  Share Name:       $SHARE_NAME"
    echo "  VM Prefix:        $VM_PREFIX"
    echo "  VM Count:         $VM_COUNT"
    echo ""
    
    # Step 1: Validate prerequisites
    log INFO "Step 1/5: Validating storage account..."
    if ! validate_storage_account; then
        log ERROR "Storage validation failed"
        exit 1
    fi
    
    # Step 2: Validate session hosts
    log INFO "Step 2/5: Validating session hosts..."
    if ! validate_session_hosts; then
        log ERROR "Session host validation failed"
        exit 1
    fi
    
    # Step 3: Configure storage RBAC
    log INFO "Step 3/5: Configuring storage RBAC..."
    configure_storage_rbac
    
    # Step 4: Configure FSLogix on each host
    log INFO "Step 4/5: Configuring FSLogix on session hosts..."
    local config_success=0
    
    for i in $(seq 1 "$VM_COUNT"); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        
        # Check if VM exists and is running
        local power_state=$(az vm get-instance-view --name "$vm_name" \
            --resource-group "$RESOURCE_GROUP" \
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv 2>/dev/null || echo "")
        
        if [[ "$power_state" == "VM running" ]]; then
            if configure_fslogix_on_host "$vm_name"; then
                ((config_success++))
            fi
        else
            log WARN "Skipping $vm_name (not running)"
        fi
    done
    
    log INFO "Configured FSLogix on $config_success session host(s)"
    
    # Step 5: Validate setup
    log INFO "Step 5/5: Validating FSLogix setup..."
    validate_fslogix_setup
    
    # Summary
    echo ""
    echo "============================================================"
    echo "  FSLogix Configuration Complete"
    echo "============================================================"
    echo ""
    echo "  Profile Share: \\\\$STORAGE_ACCOUNT.file.core.windows.net\\$SHARE_NAME"
    echo "  Hosts Configured: $config_success"
    echo "  Log File: $LOG_FILE"
    echo ""
    echo "  Next Steps:"
    echo "    1. Reboot session hosts to fully activate FSLogix"
    echo "    2. Test user login and verify profile creation"
    echo "    3. Monitor profile sizes in Azure portal"
    echo ""
    
    return 0
}

main "$@"
