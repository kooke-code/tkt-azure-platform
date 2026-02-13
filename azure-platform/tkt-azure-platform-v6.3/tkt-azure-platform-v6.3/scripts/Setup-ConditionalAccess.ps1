#Requires -Modules Microsoft.Graph.Identity.SignIns

<#
.SYNOPSIS
    Deploys Conditional Access policies for TKT Philippines AVD platform.

.DESCRIPTION
    Creates named locations and Conditional Access policies for:
    - MFA requirement for all AVD access
    - Geographic restriction (Philippines and Belgium only)
    - Legacy authentication blocking

.PARAMETER SecurityGroupName
    Name of the security group containing AVD users.
    Default: TKT-Philippines-AVD-Users

.PARAMETER ReportOnlyMode
    Deploy policies in report-only mode for testing.
    Default: $true

.EXAMPLE
    .\Setup-ConditionalAccess.ps1
    Deploys policies in report-only mode.

.EXAMPLE
    .\Setup-ConditionalAccess.ps1 -ReportOnlyMode $false
    Deploys policies in enforced mode.

.NOTES
    Version: 5.0
    Date: 2026-02-13
    Requires: Global Administrator or Conditional Access Administrator role
#>

param(
    [string]$SecurityGroupName = "TKT-Philippines-AVD-Users",
    [bool]$ReportOnlyMode = $true
)

$ErrorActionPreference = "Stop"

# AVD Application ID
$AVDAppId = "9cdead84-a844-4324-93f2-b2e6bb768d07"

# Global Admin role ID (excluded from policies to prevent lockout)
$GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  TKT Philippines AVD - Conditional Access Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess", "Policy.Read.All", "Directory.Read.All" -NoWelcome
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

# Get security group
Write-Host "Finding security group: $SecurityGroupName..." -ForegroundColor Yellow
$group = Get-MgGroup -Filter "displayName eq '$SecurityGroupName'" | Select-Object -First 1
if (-not $group) {
    Write-Error "Security group '$SecurityGroupName' not found"
    exit 1
}
Write-Host "✓ Found group: $($group.DisplayName) ($($group.Id))" -ForegroundColor Green

# Policy state
$policyState = if ($ReportOnlyMode) { "enabledForReportingButNotEnforced" } else { "enabled" }
Write-Host ""
Write-Host "Policy mode: $policyState" -ForegroundColor $(if ($ReportOnlyMode) { "Yellow" } else { "Red" })
Write-Host ""

#region Named Locations

Write-Host "Creating named locations..." -ForegroundColor Yellow

# Philippines
$phLocation = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq 'Philippines'" | Select-Object -First 1
if (-not $phLocation) {
    $phParams = @{
        "@odata.type" = "#microsoft.graph.countryNamedLocation"
        DisplayName = "Philippines"
        CountriesAndRegions = @("PH")
        IncludeUnknownCountriesAndRegions = $false
    }
    $phLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $phParams
    Write-Host "  ✓ Created: Philippines" -ForegroundColor Green
}
else {
    Write-Host "  → Philippines already exists" -ForegroundColor Gray
}

# Belgium
$beLocation = Get-MgIdentityConditionalAccessNamedLocation -Filter "displayName eq 'Belgium'" | Select-Object -First 1
if (-not $beLocation) {
    $beParams = @{
        "@odata.type" = "#microsoft.graph.countryNamedLocation"
        DisplayName = "Belgium"
        CountriesAndRegions = @("BE")
        IncludeUnknownCountriesAndRegions = $false
    }
    $beLocation = New-MgIdentityConditionalAccessNamedLocation -BodyParameter $beParams
    Write-Host "  ✓ Created: Belgium" -ForegroundColor Green
}
else {
    Write-Host "  → Belgium already exists" -ForegroundColor Gray
}

#endregion

#region Conditional Access Policies

Write-Host ""
Write-Host "Creating Conditional Access policies..." -ForegroundColor Yellow

# Policy 1: Require MFA
$mfaPolicyName = "TKT-PH-AVD-Require-MFA"
$existingMfaPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$mfaPolicyName'" | Select-Object -First 1

if (-not $existingMfaPolicy) {
    $mfaPolicy = @{
        DisplayName = $mfaPolicyName
        State = $policyState
        Conditions = @{
            Applications = @{
                IncludeApplications = @($AVDAppId)
            }
            Users = @{
                IncludeGroups = @($group.Id)
                ExcludeRoles = @($GlobalAdminRoleId)
            }
            ClientAppTypes = @("browser", "mobileAppsAndDesktopClients")
        }
        GrantControls = @{
            Operator = "OR"
            BuiltInControls = @("mfa")
        }
        SessionControls = @{
            SignInFrequency = @{
                Value = 8
                Type = "hours"
                IsEnabled = $true
            }
        }
    }
    
    New-MgIdentityConditionalAccessPolicy -BodyParameter $mfaPolicy | Out-Null
    Write-Host "  ✓ Created: $mfaPolicyName" -ForegroundColor Green
}
else {
    Write-Host "  → $mfaPolicyName already exists" -ForegroundColor Gray
}

# Policy 2: Location Restriction
$locationPolicyName = "TKT-PH-AVD-Location-Restriction"
$existingLocationPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$locationPolicyName'" | Select-Object -First 1

if (-not $existingLocationPolicy) {
    $locationPolicy = @{
        DisplayName = $locationPolicyName
        State = $policyState
        Conditions = @{
            Applications = @{
                IncludeApplications = @($AVDAppId)
            }
            Users = @{
                IncludeGroups = @($group.Id)
                ExcludeRoles = @($GlobalAdminRoleId)
            }
            Locations = @{
                IncludeLocations = @("All")
                ExcludeLocations = @($phLocation.Id, $beLocation.Id)
            }
        }
        GrantControls = @{
            Operator = "OR"
            BuiltInControls = @("block")
        }
    }
    
    New-MgIdentityConditionalAccessPolicy -BodyParameter $locationPolicy | Out-Null
    Write-Host "  ✓ Created: $locationPolicyName" -ForegroundColor Green
}
else {
    Write-Host "  → $locationPolicyName already exists" -ForegroundColor Gray
}

# Policy 3: Block Legacy Auth
$legacyPolicyName = "TKT-PH-AVD-Block-Legacy-Auth"
$existingLegacyPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$legacyPolicyName'" | Select-Object -First 1

if (-not $existingLegacyPolicy) {
    $legacyPolicy = @{
        DisplayName = $legacyPolicyName
        State = "enabled"  # Always enforce legacy auth blocking
        Conditions = @{
            Applications = @{
                IncludeApplications = @("All")
            }
            Users = @{
                IncludeGroups = @($group.Id)
            }
            ClientAppTypes = @("exchangeActiveSync", "other")
        }
        GrantControls = @{
            Operator = "OR"
            BuiltInControls = @("block")
        }
    }
    
    New-MgIdentityConditionalAccessPolicy -BodyParameter $legacyPolicy | Out-Null
    Write-Host "  ✓ Created: $legacyPolicyName" -ForegroundColor Green
}
else {
    Write-Host "  → $legacyPolicyName already exists" -ForegroundColor Gray
}

#endregion

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Conditional Access Setup Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Named Locations:" -ForegroundColor White
Write-Host "  • Philippines (PH)" -ForegroundColor Gray
Write-Host "  • Belgium (BE)" -ForegroundColor Gray
Write-Host ""
Write-Host "Policies Created:" -ForegroundColor White
Write-Host "  • TKT-PH-AVD-Require-MFA" -ForegroundColor Gray
Write-Host "  • TKT-PH-AVD-Location-Restriction" -ForegroundColor Gray
Write-Host "  • TKT-PH-AVD-Block-Legacy-Auth" -ForegroundColor Gray
Write-Host ""

if ($ReportOnlyMode) {
    Write-Host "⚠ Policies are in REPORT-ONLY mode" -ForegroundColor Yellow
    Write-Host "  Test thoroughly, then run with -ReportOnlyMode `$false to enforce" -ForegroundColor Yellow
}
else {
    Write-Host "✓ Policies are ENFORCED" -ForegroundColor Green
}

Write-Host ""
Write-Host "View policies: https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies" -ForegroundColor Cyan
Write-Host ""

# Disconnect
Disconnect-MgGraph | Out-Null
