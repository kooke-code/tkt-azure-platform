# TKT Philippines AVD Platform - M365 Licensing Guide

**Version:** 9.0 | **Date:** 2026-02-17

## Overview

TKT Philippines SAP consultants need Microsoft 365 licenses for Teams access outside the AVD session (mobile/web) and for Azure Virtual Desktop entitlements. This guide documents the licensing options.

## Minimum License Requirements

| Requirement | License Needed | Notes |
|-------------|---------------|-------|
| **Azure Virtual Desktop access** | Windows E3 or M365 F3+ | AVD requires Windows Enterprise entitlement |
| **Teams (outside AVD)** | M365 F3 or Business Basic | For mobile/web Teams access |
| **Teams (inside AVD)** | Included with AVD | WebRTC optimized client on session host |
| **Outlook/Office web apps** | Included with F3 | Web-only, not desktop apps |
| **OneDrive for Business** | M365 Business Basic+ | Only if personal cloud storage needed |

## Recommended License Options

### Option 1: Microsoft 365 F3 (Recommended)
- **Cost:** ~EUR 3.70/user/month
- **Includes:** Teams, Outlook web, Office web apps, Windows Enterprise
- **Best for:** Consultants who primarily use AVD and need Teams on mobile
- **Does NOT include:** OneDrive, full Office desktop apps

### Option 2: Microsoft 365 Business Basic
- **Cost:** ~EUR 5.60/user/month
- **Includes:** Everything in F3 + OneDrive (1TB) + SharePoint
- **Best for:** Consultants who need personal OneDrive storage
- **Does NOT include:** Windows Enterprise (need separate license)

### Option 3: Microsoft 365 E3
- **Cost:** ~EUR 33.00/user/month
- **Includes:** Full Office desktop apps, OneDrive, SharePoint, Windows E3
- **Best for:** Power users who need full Office suite
- **Overkill for:** Browser-based SAP consultants

## Recommendation for TKT Philippines

**Use M365 F3** for all 6 consultants:
- Total: 6 x EUR 3.70 = **EUR 22.20/month**
- Provides Teams access on mobile (outside AVD)
- Provides Windows Enterprise entitlement for AVD
- Office web apps sufficient for occasional Excel/Outlook use
- SAP Fiori and Zoho Desk are browser-based (no Office license needed)

## License Assignment

Licenses can be assigned:
1. **Azure Portal:** Entra ID > Users > Licenses
2. **Microsoft 365 Admin Center:** Users > Active Users > Manage licenses
3. **PowerShell:**
   ```powershell
   Set-MgUserLicense -UserId "user@domain.com" -AddLicenses @{SkuId = "SPE_F1"}
   ```

## Azure Virtual Desktop Licensing

AVD multi-session Windows 11 Enterprise requires one of:
- Microsoft 365 F3, E3, E5, A3, A5, Business Premium
- Windows Enterprise E3, E5
- Windows Education A3, A5

The F3 license covers this requirement at the lowest cost.

## Cost Summary (6 consultants)

| Component | Monthly Cost |
|-----------|-------------|
| M365 F3 licenses (6x) | EUR 22.20 |
| AVD platform (3x D4s_v5) | EUR 390.00 |
| Azure Firewall Basic | EUR 280.00 |
| **Total** | **EUR 692.20** |
| **Per consultant** | **EUR 115.37** |
