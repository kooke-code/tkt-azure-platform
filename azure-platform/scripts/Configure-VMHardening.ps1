#===============================================================================
# TKT Philippines SAP Platform - VM Hardening Script
# Version: 1.0
# Date: 2026-01-30
#
# This PowerShell script applies security hardening to Windows VMs including:
#   - USB device blocking
#   - Local storage restrictions
#   - RDP security settings
#   - Folder redirection to Azure Files
#
# Prerequisites:
#   - Run as Administrator
#   - Azure Files share must be mounted
#
# Usage:
#   .\Configure-VMHardening.ps1 -StorageAccount "stcustomer001ph" -Username "ph-lead-001"
#===============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccount,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [string]$ShareName = "consultant-data",
    
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------

$AzureFilesPath = "\\$StorageAccount.file.core.windows.net\$ShareName"
$UserFolderPath = "$AzureFilesPath\$Username"

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-AdminPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = "DWord"
    )
    
    if ($DryRun) {
        Write-Log "[DRY RUN] Would set: $Path\$Name = $Value" "INFO"
        return
    }
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
    Write-Log "Set: $Path\$Name = $Value" "SUCCESS"
}

#-------------------------------------------------------------------------------
# USB Device Blocking
#-------------------------------------------------------------------------------

function Disable-USBStorage {
    Write-Log "Configuring USB storage device blocking..." "INFO"
    
    # Deny execute access to removable storage
    $usbPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
    
    # All removable storage classes
    Set-RegistryValue -Path "$usbPath\{53f56307-b6bf-11d0-94f2-00a0c91efb8b}" -Name "Deny_All" -Value 1
    Set-RegistryValue -Path "$usbPath\{53f56308-b6bf-11d0-94f2-00a0c91efb8b}" -Name "Deny_All" -Value 1
    Set-RegistryValue -Path "$usbPath\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}" -Name "Deny_All" -Value 1
    
    # Deny read/write to removable disks
    Set-RegistryValue -Path "$usbPath" -Name "Deny_Read" -Value 1
    Set-RegistryValue -Path "$usbPath" -Name "Deny_Write" -Value 1
    
    # Disable USB mass storage driver
    $usbStorPath = "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR"
    Set-RegistryValue -Path $usbStorPath -Name "Start" -Value 4
    
    Write-Log "USB storage blocking configured." "SUCCESS"
}

#-------------------------------------------------------------------------------
# RDP Security Settings
#-------------------------------------------------------------------------------

function Configure-RDPSecurity {
    Write-Log "Configuring RDP security settings..." "INFO"
    
    $rdpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    
    # Disable clipboard redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisableClip" -Value 1
    
    # Disable drive redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisableCdm" -Value 1
    
    # Disable printer redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisableCpm" -Value 1
    
    # Disable COM port redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisableCcm" -Value 1
    
    # Disable LPT port redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisableLPT" -Value 1
    
    # Disable PnP device redirection
    Set-RegistryValue -Path $rdpPath -Name "fDisablePNPRedir" -Value 1
    
    # Set session timeout (8 hours)
    Set-RegistryValue -Path $rdpPath -Name "MaxIdleTime" -Value 28800000
    Set-RegistryValue -Path $rdpPath -Name "MaxConnectionTime" -Value 28800000
    
    # Require NLA
    Set-RegistryValue -Path $rdpPath -Name "UserAuthentication" -Value 1
    
    # Set encryption level to High
    Set-RegistryValue -Path $rdpPath -Name "MinEncryptionLevel" -Value 3
    
    Write-Log "RDP security configured." "SUCCESS"
}

#-------------------------------------------------------------------------------
# Folder Redirection
#-------------------------------------------------------------------------------

function Configure-FolderRedirection {
    Write-Log "Configuring folder redirection to Azure Files..." "INFO"
    
    if (-not (Test-Path $AzureFilesPath)) {
        Write-Log "ERROR: Cannot access Azure Files at $AzureFilesPath" "ERROR"
        Write-Log "Please mount the Azure Files share first." "ERROR"
        return $false
    }
    
    if (-not (Test-Path $UserFolderPath)) {
        Write-Log "Creating user folder: $UserFolderPath" "INFO"
        if (-not $DryRun) {
            New-Item -Path $UserFolderPath -ItemType Directory -Force | Out-Null
            New-Item -Path "$UserFolderPath\Desktop" -ItemType Directory -Force | Out-Null
            New-Item -Path "$UserFolderPath\Documents" -ItemType Directory -Force | Out-Null
            New-Item -Path "$UserFolderPath\Downloads" -ItemType Directory -Force | Out-Null
        }
    }
    
    $shellFoldersPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    
    Set-RegistryValue -Path $shellFoldersPath -Name "Desktop" -Value "$UserFolderPath\Desktop" -Type "ExpandString"
    Set-RegistryValue -Path $shellFoldersPath -Name "Personal" -Value "$UserFolderPath\Documents" -Type "ExpandString"
    Set-RegistryValue -Path $shellFoldersPath -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Value "$UserFolderPath\Downloads" -Type "ExpandString"
    
    Write-Log "Folder redirection configured." "SUCCESS"
    return $true
}

#-------------------------------------------------------------------------------
# Windows Defender Configuration
#-------------------------------------------------------------------------------

function Configure-WindowsDefender {
    Write-Log "Configuring Windows Defender..." "INFO"
    
    if ($DryRun) {
        Write-Log "[DRY RUN] Would configure Windows Defender settings" "INFO"
        return
    }
    
    Set-MpPreference -DisableRealtimeMonitoring $false
    Set-MpPreference -MAPSReporting Advanced
    Set-MpPreference -SubmitSamplesConsent SendAllSamples
    Set-MpPreference -DisableBehaviorMonitoring $false
    Set-MpPreference -PUAProtection Enabled
    
    Write-Log "Windows Defender configured." "SUCCESS"
}

#-------------------------------------------------------------------------------
# Audit Policy Configuration
#-------------------------------------------------------------------------------

function Configure-AuditPolicy {
    Write-Log "Configuring audit policies for monitoring..." "INFO"
    
    if ($DryRun) {
        Write-Log "[DRY RUN] Would configure audit policies" "INFO"
        return
    }
    
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
    auditpol /set /subcategory:"Logon" /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff" /success:enable
    auditpol /set /subcategory:"File System" /success:enable /failure:enable
    auditpol /set /subcategory:"Removable Storage" /success:enable /failure:enable
    
    $auditPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    Set-RegistryValue -Path $auditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1
    
    Write-Log "Audit policies configured." "SUCCESS"
}

#-------------------------------------------------------------------------------
# Main Execution
#-------------------------------------------------------------------------------

function Main {
    Write-Log "==========================================" "INFO"
    Write-Log "TKT Philippines SAP Platform" "INFO"
    Write-Log "VM Hardening Script" "INFO"
    Write-Log "==========================================" "INFO"
    
    if ($DryRun) {
        Write-Log "*** DRY RUN MODE - No changes will be made ***" "WARNING"
    }
    
    if (-not (Test-AdminPrivileges)) {
        Write-Log "ERROR: This script must be run as Administrator." "ERROR"
        exit 1
    }
    
    Write-Log "Configuration:" "INFO"
    Write-Log "  Storage Account: $StorageAccount" "INFO"
    Write-Log "  Username: $Username" "INFO"
    Write-Log "  Azure Files Path: $AzureFilesPath" "INFO"
    
    Disable-USBStorage
    Configure-RDPSecurity
    Configure-FolderRedirection
    Configure-WindowsDefender
    Configure-AuditPolicy
    
    Write-Log "==========================================" "INFO"
    Write-Log "VM Hardening Complete!" "SUCCESS"
    Write-Log "==========================================" "INFO"
    Write-Log "IMPORTANT: A restart is recommended." "WARNING"
    
    if (-not $DryRun) {
        $restart = Read-Host "Restart now? (y/n)"
        if ($restart -eq 'y') {
            Restart-Computer -Force
        }
    }
}

Main
