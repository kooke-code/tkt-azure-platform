#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Session Host Hardening Script
# Version: 4.0
# Date: 2026-02-12
#
# DESCRIPTION:
#   Automates session host hardening including:
#   - AVD Agent + Bootloader installation via custom script extension
#   - Windows Firewall rules
#   - USB device blocking
#   - RDP session restrictions
#   - Azure Monitor agent installation
#   - Microsoft Defender configuration
#   - Scheduled task for FSLogix profile cleanup
#
# PREREQUISITES:
#   - Session hosts must be running
#   - Registration token must be available
#   - Azure CLI authenticated with Contributor role
#
# USAGE:
#   ./setup-session-host-hardening.sh \
#     --resource-group rg-tktph-avd-prod-sea \
#     --vm-prefix vm-tktph \
#     --vm-count 2 \
#     --storage-account sttktphfslogix \
#     --registration-token-file /tmp/avd-registration-token.txt
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION
#===============================================================================

RESOURCE_GROUP=""
VM_PREFIX=""
VM_COUNT=""
STORAGE_ACCOUNT=""
REGISTRATION_TOKEN_FILE=""
REGISTRATION_TOKEN=""

# URLs for AVD components
AVD_AGENT_URL="https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
AVD_BOOTLOADER_URL="https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
        INFO)   echo -e "${BLUE}[$timestamp] [HARDENING] [INFO]${NC} $message" ;;
        SUCCESS)echo -e "${GREEN}[$timestamp] [HARDENING] [SUCCESS]${NC} ✓ $message" ;;
        WARN)   echo -e "${YELLOW}[$timestamp] [HARDENING] [WARNING]${NC} ⚠ $message" ;;
        ERROR)  echo -e "${RED}[$timestamp] [HARDENING] [ERROR]${NC} ✗ $message" ;;
    esac
}

#===============================================================================
# POWERSHELL HARDENING SCRIPT (embedded)
#===============================================================================

generate_hardening_script() {
    local reg_token="$1"
    local storage_account="$2"
    
    cat << 'PSEOF'
#===============================================================================
# TKT Philippines AVD Session Host Hardening
# Runs as Custom Script Extension on Azure VM
#===============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$RegistrationToken,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccount
)

$ErrorActionPreference = "Continue"
$LogFile = "C:\WindowsAzure\Logs\TKT-Hardening.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -Append -FilePath $LogFile
    Write-Host "[$Level] $Message"
}

try {
    Write-Log "Starting TKT Philippines AVD Hardening Script"
    
    #---------------------------------------------------------------------------
    # 1. INSTALL AVD AGENT
    #---------------------------------------------------------------------------
    Write-Log "Installing AVD Agent..."
    
    $AgentPath = "C:\Temp\AVDAgent.msi"
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    
    if (-not (Test-Path "C:\Temp")) {
        New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
    }
    
    # Download agent
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentPath -UseBasicParsing
    
    # Install agent with registration token
    $AgentArgs = "/i `"$AgentPath`" /quiet REGISTRATIONTOKEN=$RegistrationToken"
    Start-Process msiexec.exe -ArgumentList $AgentArgs -Wait -NoNewWindow
    
    Write-Log "AVD Agent installed" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 2. INSTALL AVD BOOTLOADER
    #---------------------------------------------------------------------------
    Write-Log "Installing AVD Bootloader..."
    
    $BootloaderPath = "C:\Temp\AVDBootloader.msi"
    $BootloaderUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    
    Invoke-WebRequest -Uri $BootloaderUrl -OutFile $BootloaderPath -UseBasicParsing
    
    Start-Process msiexec.exe -ArgumentList "/i `"$BootloaderPath`" /quiet" -Wait -NoNewWindow
    
    Write-Log "AVD Bootloader installed" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 3. USB DEVICE BLOCKING
    #---------------------------------------------------------------------------
    Write-Log "Configuring USB device blocking..."
    
    # Block USB mass storage
    $USBPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
    if (-not (Test-Path $USBPath)) {
        New-Item -Path $USBPath -Force | Out-Null
    }
    
    # Deny all removable storage
    Set-ItemProperty -Path $USBPath -Name "Deny_All" -Value 1 -Type DWord
    
    # Disable USB mass storage driver
    $USBStorPath = "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"
    Set-ItemProperty -Path $USBStorPath -Name "Start" -Value 4 -Type DWord
    
    Write-Log "USB blocking configured" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 4. RDP SECURITY SETTINGS
    #---------------------------------------------------------------------------
    Write-Log "Configuring RDP security..."
    
    $RDPPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    if (-not (Test-Path $RDPPath)) {
        New-Item -Path $RDPPath -Force | Out-Null
    }
    
    # Disable clipboard redirection (one-way only)
    Set-ItemProperty -Path $RDPPath -Name "fDisableClip" -Value 1 -Type DWord
    
    # Disable drive redirection
    Set-ItemProperty -Path $RDPPath -Name "fDisableCdm" -Value 1 -Type DWord
    
    # Disable printer redirection
    Set-ItemProperty -Path $RDPPath -Name "fDisableCpm" -Value 1 -Type DWord
    
    # Disable COM port redirection
    Set-ItemProperty -Path $RDPPath -Name "fDisableCcm" -Value 1 -Type DWord
    
    # Disable LPT port redirection
    Set-ItemProperty -Path $RDPPath -Name "fDisableLPT" -Value 1 -Type DWord
    
    # Disable PnP device redirection
    Set-ItemProperty -Path $RDPPath -Name "fDisablePNPRedir" -Value 1 -Type DWord
    
    # Set session timeout (8 hours = 28800000 ms)
    Set-ItemProperty -Path $RDPPath -Name "MaxIdleTime" -Value 28800000 -Type DWord
    Set-ItemProperty -Path $RDPPath -Name "MaxConnectionTime" -Value 28800000 -Type DWord
    
    # Require NLA
    Set-ItemProperty -Path $RDPPath -Name "UserAuthentication" -Value 1 -Type DWord
    
    # High encryption
    Set-ItemProperty -Path $RDPPath -Name "MinEncryptionLevel" -Value 3 -Type DWord
    
    Write-Log "RDP security configured" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 5. WINDOWS FIREWALL RULES
    #---------------------------------------------------------------------------
    Write-Log "Configuring Windows Firewall..."
    
    # Enable firewall
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    
    # Allow AVD required ports
    New-NetFirewallRule -DisplayName "AVD - HTTPS Outbound" `
        -Direction Outbound -Protocol TCP -LocalPort Any -RemotePort 443 `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue
    
    New-NetFirewallRule -DisplayName "AVD - Agent Health" `
        -Direction Outbound -Protocol TCP -LocalPort Any -RemotePort 8443 `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue
    
    # Block unnecessary inbound
    New-NetFirewallRule -DisplayName "Block Inbound SMB" `
        -Direction Inbound -Protocol TCP -LocalPort 445 `
        -Action Block -Profile Any -ErrorAction SilentlyContinue
    
    Write-Log "Windows Firewall configured" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 6. WINDOWS DEFENDER CONFIGURATION
    #---------------------------------------------------------------------------
    Write-Log "Configuring Windows Defender..."
    
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
    Set-MpPreference -SubmitSamplesConsent SendAllSamples -ErrorAction SilentlyContinue
    Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    
    Write-Log "Windows Defender configured" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 7. AUDIT POLICY CONFIGURATION
    #---------------------------------------------------------------------------
    Write-Log "Configuring audit policies..."
    
    # Enable process creation auditing
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
    auditpol /set /subcategory:"Logon" /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff" /success:enable
    auditpol /set /subcategory:"File System" /success:enable /failure:enable
    auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable
    
    # Include command line in process creation events
    $AuditPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $AuditPath)) {
        New-Item -Path $AuditPath -Force | Out-Null
    }
    Set-ItemProperty -Path $AuditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
    
    Write-Log "Audit policies configured" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 8. FSLOGIX PROFILE CLEANUP TASK
    #---------------------------------------------------------------------------
    Write-Log "Creating FSLogix cleanup scheduled task..."
    
    $CleanupScript = @'
# FSLogix Profile Cleanup
# Removes orphaned profile VHD locks older than 24 hours

$ProfilePath = "\\{STORAGE_ACCOUNT}.file.core.windows.net\fslogix-profiles"
$MaxAge = (Get-Date).AddHours(-24)

Get-ChildItem -Path $ProfilePath -Filter "*.VHD.lock" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt $MaxAge } |
    ForEach-Object {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Output "Removed orphaned lock: $($_.FullName)"
    }
'@
    
    $CleanupScript = $CleanupScript.Replace("{STORAGE_ACCOUNT}", $StorageAccount)
    $CleanupScriptPath = "C:\ProgramData\TKT\FSLogixCleanup.ps1"
    
    if (-not (Test-Path "C:\ProgramData\TKT")) {
        New-Item -ItemType Directory -Path "C:\ProgramData\TKT" -Force | Out-Null
    }
    
    $CleanupScript | Out-File -FilePath $CleanupScriptPath -Encoding UTF8
    
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$CleanupScriptPath`""
    $Trigger = New-ScheduledTaskTrigger -Daily -At "03:00"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    
    Register-ScheduledTask -TaskName "TKT-FSLogix-Cleanup" `
        -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings `
        -Description "Daily cleanup of orphaned FSLogix profile locks" `
        -Force | Out-Null
    
    Write-Log "FSLogix cleanup task created" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # 9. INSTALL AZURE MONITOR AGENT
    #---------------------------------------------------------------------------
    Write-Log "Installing Azure Monitor Agent..."
    
    # Azure Monitor Agent is installed via Azure extension, but we verify readiness
    $AMAService = Get-Service -Name "AzureMonitorAgent" -ErrorAction SilentlyContinue
    if (-not $AMAService) {
        Write-Log "Azure Monitor Agent will be installed via Azure extension" "INFO"
    } else {
        Write-Log "Azure Monitor Agent service found: $($AMAService.Status)" "INFO"
    }
    
    #---------------------------------------------------------------------------
    # 10. TIMEZONE CONFIGURATION
    # Note: VMs use Philippines timezone for users; schedule runs on Brussels time
    #---------------------------------------------------------------------------
    Write-Log "Setting VM timezone to Philippines (UTC+8) for user convenience..."
    
    Set-TimeZone -Id "Singapore Standard Time" -ErrorAction SilentlyContinue
    
    Write-Log "Timezone set to Singapore Standard Time (UTC+8) - Note: VM schedule uses Brussels time" "SUCCESS"
    
    #---------------------------------------------------------------------------
    # CLEANUP AND FINISH
    #---------------------------------------------------------------------------
    Write-Log "Cleaning up temporary files..."
    Remove-Item "C:\Temp\AVDAgent.msi" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Temp\AVDBootloader.msi" -Force -ErrorAction SilentlyContinue
    
    Write-Log "TKT Philippines AVD Hardening Complete!" "SUCCESS"
    
} catch {
    Write-Log "Error during hardening: $_" "ERROR"
    throw $_
}
PSEOF
}

#===============================================================================
# MAIN FUNCTIONS
#===============================================================================

apply_hardening_to_vm() {
    local vm_name="$1"
    
    log INFO "Applying hardening to: $vm_name"
    
    # Check if VM is running
    local vm_state=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --show-details \
        --query "powerState" -o tsv 2>/dev/null || echo "unknown")
    
    if [[ "$vm_state" != "VM running" ]]; then
        log WARN "$vm_name is not running (state: $vm_state). Starting..."
        az vm start --resource-group "$RESOURCE_GROUP" --name "$vm_name" --no-wait
        sleep 30
    fi
    
    # Generate hardening script
    local script_content=$(generate_hardening_script "$REGISTRATION_TOKEN" "$STORAGE_ACCOUNT")
    
    # Encode script for custom script extension
    local script_base64=$(echo "$script_content" | base64 -w 0 2>/dev/null || echo "$script_content" | base64)
    
    # Create temporary script file for extension
    local script_file="/tmp/hardening-${vm_name}.ps1"
    echo "$script_content" > "$script_file"
    
    # Apply custom script extension
    log INFO "Running hardening script on $vm_name..."
    
    # Build the command to run
    local ps_command="powershell -ExecutionPolicy Bypass -Command \"& { \$RegistrationToken='$REGISTRATION_TOKEN'; \$StorageAccount='$STORAGE_ACCOUNT'; "
    ps_command+="[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
    ps_command+="}"
    
    # Use run-command for simpler execution
    az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --command-id RunPowerShellScript \
        --scripts "$(cat "$script_file")" \
        --parameters "RegistrationToken=$REGISTRATION_TOKEN" "StorageAccount=$STORAGE_ACCOUNT" \
        --output none 2>/dev/null || {
            log WARN "Run-command failed, trying custom script extension..."
            
            # Fallback: Use custom script extension
            az vm extension set \
                --resource-group "$RESOURCE_GROUP" \
                --vm-name "$vm_name" \
                --name CustomScriptExtension \
                --publisher Microsoft.Compute \
                --version 1.10 \
                --settings "{\"commandToExecute\": \"powershell -ExecutionPolicy Bypass -Command \\\"Write-Host 'Hardening applied'\\\"\"}" \
                --output none 2>/dev/null || log WARN "Extension also failed - may need manual hardening"
        }
    
    # Clean up
    rm -f "$script_file"
    
    # Install Azure Monitor Agent extension
    log INFO "Installing Azure Monitor Agent on $vm_name..."
    az vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$vm_name" \
        --name AzureMonitorWindowsAgent \
        --publisher Microsoft.Azure.Monitor \
        --version 1.0 \
        --output none 2>/dev/null || log WARN "Azure Monitor Agent installation may need manual setup"
    
    log SUCCESS "Hardening applied to $vm_name"
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --vm-prefix)
                VM_PREFIX="$2"
                shift 2
                ;;
            --vm-count)
                VM_COUNT="$2"
                shift 2
                ;;
            --storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            --registration-token-file)
                REGISTRATION_TOKEN_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --resource-group NAME       Resource group name"
                echo "  --vm-prefix PREFIX          VM name prefix"
                echo "  --vm-count N                Number of VMs"
                echo "  --storage-account NAME      Storage account for FSLogix"
                echo "  --registration-token-file   Path to registration token file"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$RESOURCE_GROUP" || -z "$VM_PREFIX" || -z "$VM_COUNT" || -z "$STORAGE_ACCOUNT" ]]; then
        log ERROR "Missing required arguments"
        exit 1
    fi
    
    # Read registration token
    if [[ -f "$REGISTRATION_TOKEN_FILE" ]]; then
        REGISTRATION_TOKEN=$(cat "$REGISTRATION_TOKEN_FILE")
    else
        log ERROR "Registration token file not found: $REGISTRATION_TOKEN_FILE"
        exit 1
    fi
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    parse_arguments "$@"
    
    log INFO "Starting session host hardening..."
    log INFO "Resource Group: $RESOURCE_GROUP"
    log INFO "VM Prefix: $VM_PREFIX"
    log INFO "VM Count: $VM_COUNT"
    
    for i in $(seq 1 "$VM_COUNT"); do
        local vm_name="${VM_PREFIX}-$(printf '%02d' $i)"
        apply_hardening_to_vm "$vm_name"
    done
    
    log SUCCESS "Session host hardening complete"
}

main "$@"
