#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Session Host Hardening Script
# Version: 3.0
# Date: 2026-02-01
#
# This script generates a PowerShell script to harden AVD session hosts.
# Run the generated script ON EACH SESSION HOST.
#
# Usage:
#   chmod +x setup-hardening.sh
#   ./setup-hardening.sh
#   # Copy output script to session hosts and run as Administrator
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------

STORAGE_ACCOUNT="sttktphfslogix"
FSLOGIX_SHARE="fslogix-profiles"
OUTPUT_FILE="/tmp/Configure-AVDSessionHost.ps1"

#-------------------------------------------------------------------------------
# GENERATE POWERSHELL SCRIPT
#-------------------------------------------------------------------------------

cat > "$OUTPUT_FILE" << 'POWERSHELL_SCRIPT'
#===============================================================================
# TKT Philippines AVD Platform - Session Host Configuration
# Version: 3.0
# Date: 2026-02-01
#
# Run this script ON EACH SESSION HOST as Administrator
#
# This script:
#   1. Installs and configures FSLogix
#   2. Configures Windows security settings
#   3. Optimizes for AVD performance
#   4. Installs required applications
#===============================================================================

#Requires -RunAsAdministrator

param(
    [string]$StorageAccount = "sttktphfslogix",
    [string]$FileShare = "fslogix-profiles"
)

$ErrorActionPreference = "Stop"

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

#-------------------------------------------------------------------------------
# INSTALL FSLOGIX
#-------------------------------------------------------------------------------

function Install-FSLogix {
    Write-Log "Installing FSLogix..."
    
    $fslogixUrl = "https://aka.ms/fslogix_download"
    $downloadPath = "$env:TEMP\FSLogix.zip"
    $extractPath = "$env:TEMP\FSLogix"
    
    # Download FSLogix
    Write-Log "Downloading FSLogix..."
    Invoke-WebRequest -Uri $fslogixUrl -OutFile $downloadPath -UseBasicParsing
    
    # Extract
    Write-Log "Extracting FSLogix..."
    Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
    
    # Install FSLogix Apps
    Write-Log "Installing FSLogix Apps..."
    $installer = Get-ChildItem -Path $extractPath -Recurse -Filter "FSLogixAppsSetup.exe" | Select-Object -First 1
    Start-Process -FilePath $installer.FullName -ArgumentList "/install /quiet /norestart" -Wait
    
    # Cleanup
    Remove-Item -Path $downloadPath -Force
    Remove-Item -Path $extractPath -Recurse -Force
    
    Write-Log "FSLogix installed" "SUCCESS"
}

#-------------------------------------------------------------------------------
# CONFIGURE FSLOGIX
#-------------------------------------------------------------------------------

function Configure-FSLogix {
    param(
        [string]$StorageAccount,
        [string]$FileShare
    )
    
    Write-Log "Configuring FSLogix..."
    
    $profilePath = "\\$StorageAccount.file.core.windows.net\$FileShare"
    $regPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
    
    # Create registry key if not exists
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    # Configure FSLogix settings
    $settings = @{
        "Enabled" = 1
        "VHDLocations" = $profilePath
        "DeleteLocalProfileWhenVHDShouldApply" = 1
        "FlipFlopProfileDirectoryName" = 1
        "SizeInMBs" = 10240
        "VolumeType" = "VHDX"
        "IsDynamic" = 1
        "LockedRetryCount" = 3
        "LockedRetryInterval" = 15
        "ProfileType" = 0
        "ConcurrentUserSessions" = 1
        "RoamSearch" = 0
    }
    
    foreach ($key in $settings.Keys) {
        Set-ItemProperty -Path $regPath -Name $key -Value $settings[$key]
        Write-Log "Set $key = $($settings[$key])"
    }
    
    # Configure FSLogix exclusions for antivirus
    $excludePaths = @(
        "%ProgramFiles%\FSLogix\Apps\frxdrv.sys",
        "%ProgramFiles%\FSLogix\Apps\frxdrvvt.sys",
        "%ProgramFiles%\FSLogix\Apps\frxccd.sys",
        "%TEMP%\*.VHD",
        "%TEMP%\*.VHDX",
        "%Windir%\TEMP\*.VHD",
        "%Windir%\TEMP\*.VHDX",
        "$profilePath\*.VHD",
        "$profilePath\*.VHDX"
    )
    
    $excludeProcesses = @(
        "%ProgramFiles%\FSLogix\Apps\frxccd.exe",
        "%ProgramFiles%\FSLogix\Apps\frxccds.exe",
        "%ProgramFiles%\FSLogix\Apps\frxsvc.exe"
    )
    
    # Add Windows Defender exclusions
    foreach ($path in $excludePaths) {
        Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
    }
    
    foreach ($process in $excludeProcesses) {
        Add-MpPreference -ExclusionProcess $process -ErrorAction SilentlyContinue
    }
    
    Write-Log "FSLogix configured" "SUCCESS"
}

#-------------------------------------------------------------------------------
# CONFIGURE WINDOWS SECURITY
#-------------------------------------------------------------------------------

function Configure-WindowsSecurity {
    Write-Log "Configuring Windows security..."
    
    # Enable Windows Defender
    Set-MpPreference -DisableRealtimeMonitoring $false
    Set-MpPreference -MAPSReporting Advanced
    Set-MpPreference -SubmitSamplesConsent SendAllSamples
    Set-MpPreference -DisableBehaviorMonitoring $false
    Set-MpPreference -PUAProtection Enabled
    
    # Configure audit policy for monitoring
    auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
    auditpol /set /subcategory:"Logon" /success:enable /failure:enable
    auditpol /set /subcategory:"Logoff" /success:enable
    
    # Enable command line logging
    $auditPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $auditPath)) {
        New-Item -Path $auditPath -Force | Out-Null
    }
    Set-ItemProperty -Path $auditPath -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1
    
    Write-Log "Windows security configured" "SUCCESS"
}

#-------------------------------------------------------------------------------
# CONFIGURE AVD OPTIMIZATION
#-------------------------------------------------------------------------------

function Configure-AVDOptimization {
    Write-Log "Configuring AVD optimizations..."
    
    # Disable unnecessary services for AVD
    $servicesToDisable = @(
        "DiagTrack",          # Connected User Experiences and Telemetry
        "dmwappushservice",   # WAP Push Message Routing Service
        "MapsBroker",         # Downloaded Maps Manager
        "lfsvc",              # Geolocation Service
        "SharedAccess",       # Internet Connection Sharing
        "RemoteRegistry",     # Remote Registry
        "RetailDemo"          # Retail Demo Service
    )
    
    foreach ($service in $servicesToDisable) {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Log "Disabled service: $service"
        }
    }
    
    # Disable scheduled tasks that aren't needed
    $tasksToDisable = @(
        "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
        "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
        "\Microsoft\Windows\Autochk\Proxy",
        "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
        "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
        "\Microsoft\Windows\Maps\MapsToastTask",
        "\Microsoft\Windows\Maps\MapsUpdateTask"
    )
    
    foreach ($task in $tasksToDisable) {
        Disable-ScheduledTask -TaskPath (Split-Path $task -Parent) -TaskName (Split-Path $task -Leaf) -ErrorAction SilentlyContinue
    }
    
    # Configure visual effects for performance
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
    
    Write-Log "AVD optimizations configured" "SUCCESS"
}

#-------------------------------------------------------------------------------
# CONFIGURE TIMEZONE
#-------------------------------------------------------------------------------

function Configure-Timezone {
    Write-Log "Configuring timezone for Philippines..."
    
    Set-TimeZone -Name "Singapore Standard Time"  # UTC+8, same as Philippines
    
    Write-Log "Timezone set to Singapore Standard Time (UTC+8)" "SUCCESS"
}

#-------------------------------------------------------------------------------
# INSTALL APPLICATIONS
#-------------------------------------------------------------------------------

function Install-Applications {
    Write-Log "Installing required applications..."
    
    # Microsoft Edge is pre-installed on Windows 11
    # Add any additional applications here
    
    # Example: Install 7-Zip
    # winget install -e --id 7zip.7zip --accept-source-agreements --accept-package-agreements
    
    Write-Log "Applications configured" "SUCCESS"
}

#-------------------------------------------------------------------------------
# VALIDATE NETWORK CONNECTIVITY (SMOKE TEST)
#-------------------------------------------------------------------------------

function Test-NetworkConnectivity {
    Write-Log "Testing network connectivity..."
    
    $tests = @(
        @{Host = "www.microsoft.com"; Port = 443; Description = "Microsoft services"},
        @{Host = "login.microsoftonline.com"; Port = 443; Description = "Azure AD"},
        @{Host = "rdweb.wvd.microsoft.com"; Port = 443; Description = "AVD Gateway"},
        @{Host = "www.sap.com"; Port = 443; Description = "SAP Cloud"}
    )
    
    $allPassed = $true
    
    foreach ($test in $tests) {
        $result = Test-NetConnection -ComputerName $test.Host -Port $test.Port -WarningAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            Write-Log "✓ $($test.Description) ($($test.Host):$($test.Port))" "SUCCESS"
        } else {
            Write-Log "✗ $($test.Description) ($($test.Host):$($test.Port)) - FAILED" "ERROR"
            $allPassed = $false
        }
    }
    
    # Test storage connectivity
    $storageTest = Test-NetConnection -ComputerName "$StorageAccount.file.core.windows.net" -Port 445 -WarningAction SilentlyContinue
    if ($storageTest.TcpTestSucceeded) {
        Write-Log "✓ Azure Files storage" "SUCCESS"
    } else {
        Write-Log "✗ Azure Files storage - FAILED" "ERROR"
        $allPassed = $false
    }
    
    if (-not $allPassed) {
        Write-Log "CRITICAL: Network connectivity tests failed. Fix NSG rules before proceeding!" "ERROR"
        return $false
    }
    
    Write-Log "All network connectivity tests passed" "SUCCESS"
    return $true
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

function Main {
    Write-Host ""
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "     TKT PHILIPPINES AVD - SESSION HOST CONFIGURATION" -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Run network tests first
    $networkOk = Test-NetworkConnectivity
    if (-not $networkOk) {
        Write-Host ""
        Write-Log "Aborting configuration due to network connectivity failures." "ERROR"
        Write-Log "Please fix network connectivity and run this script again." "ERROR"
        exit 1
    }
    
    Write-Host ""
    
    # Install and configure components
    Install-FSLogix
    Configure-FSLogix -StorageAccount $StorageAccount -FileShare $FileShare
    Configure-WindowsSecurity
    Configure-AVDOptimization
    Configure-Timezone
    Install-Applications
    
    Write-Host ""
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "     CONFIGURATION COMPLETE" -ForegroundColor Green
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Restart the VM: Restart-Computer -Force"
    Write-Host "  2. Verify FSLogix is running: Get-Service -Name frxsvc"
    Write-Host "  3. Test user login via AVD web client"
    Write-Host ""
    
    $restart = Read-Host "Restart now? (y/n)"
    if ($restart -eq 'y') {
        Restart-Computer -Force
    }
}

# Run main
Main
POWERSHELL_SCRIPT

#-------------------------------------------------------------------------------
# UPDATE STORAGE ACCOUNT IN SCRIPT
#-------------------------------------------------------------------------------

sed -i "s/sttktphfslogix/$STORAGE_ACCOUNT/g" "$OUTPUT_FILE"
sed -i "s/fslogix-profiles/$FSLOGIX_SHARE/g" "$OUTPUT_FILE"

#-------------------------------------------------------------------------------
# OUTPUT
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================================="
echo "     SESSION HOST HARDENING SCRIPT GENERATED"
echo "==============================================================================="
echo ""
echo "Output file: $OUTPUT_FILE"
echo ""
echo "Instructions:"
echo "  1. Copy this script to each session host"
echo "  2. Run PowerShell as Administrator"
echo "  3. Execute: .\\Configure-AVDSessionHost.ps1"
echo ""
echo "The script will:"
echo "  ✓ Test network connectivity (smoke test)"
echo "  ✓ Install and configure FSLogix"
echo "  ✓ Configure Windows security settings"
echo "  ✓ Optimize for AVD performance"
echo "  ✓ Set timezone to Philippines (UTC+8)"
echo ""
echo "==============================================================================="
echo ""

# Display the script
echo "Generated script content:"
echo "==============================================================================="
cat "$OUTPUT_FILE"
