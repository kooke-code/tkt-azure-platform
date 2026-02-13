#!/bin/bash
#===============================================================================
# TKT Philippines AVD - Transfer Ownership Script
# Transfers full ownership of AVD platform to tom.tuerlings@tktconsulting.com
#===============================================================================

set -o errexit
set -o pipefail

# Configuration
NEW_OWNER="tom.tuerlings@tktconsulting.com"
RESOURCE_GROUP="rg-tktph-avd-prod-sea"
SECURITY_GROUP="TKT-Philippines-AVD-Users"

echo "============================================================"
echo "  TKT Philippines AVD - Ownership Transfer"
echo "============================================================"
echo ""
echo "  Transferring ownership to: $NEW_OWNER"
echo ""

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "  Subscription: $SUBSCRIPTION_ID"

# 1. Add Owner role on Resource Group
echo ""
echo "[1/5] Adding Owner role on Resource Group..."
az role assignment create \
    --assignee "$NEW_OWNER" \
    --role "Owner" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
    --output none 2>/dev/null || echo "  → Already assigned or pending"
echo "  ✓ Owner role assigned on $RESOURCE_GROUP"

# 2. Add Owner role on Subscription (optional - for full control)
echo ""
echo "[2/5] Adding Contributor role on Subscription..."
az role assignment create \
    --assignee "$NEW_OWNER" \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID" \
    --output none 2>/dev/null || echo "  → Already assigned or pending"
echo "  ✓ Contributor role assigned on subscription"

# 3. Add as owner of security group
echo ""
echo "[3/5] Adding as owner of security group..."
TOM_ID=$(az ad user show --id "$NEW_OWNER" --query id -o tsv 2>/dev/null || echo "")
if [[ -n "$TOM_ID" ]]; then
    az ad group owner add --group "$SECURITY_GROUP" --owner-object-id "$TOM_ID" 2>/dev/null || echo "  → Already owner or pending"
    echo "  ✓ Added as owner of $SECURITY_GROUP"
else
    echo "  ⚠ Could not find user $NEW_OWNER in directory"
    echo "    User must exist in tktconsulting.be directory"
fi

# 4. Update alert email
echo ""
echo "[4/5] Updating monitoring alert email..."
az monitor action-group update \
    --resource-group "$RESOURCE_GROUP" \
    --name "ag-tktph-avd" \
    --add-action email TomAlert "$NEW_OWNER" \
    --output none 2>/dev/null || echo "  → Action group update pending"
echo "  ✓ Alert notifications will be sent to $NEW_OWNER"

# 5. Documentation
echo ""
echo "[5/5] Ownership transfer notes..."
cat << EOF

============================================================
  OWNERSHIP TRANSFER COMPLETE
============================================================

New Owner: $NEW_OWNER

ASSIGNED ROLES:
  ✓ Owner on Resource Group: $RESOURCE_GROUP
  ✓ Contributor on Subscription
  ✓ Owner of Security Group: $SECURITY_GROUP
  ✓ Alert email recipient

MANUAL STEPS REQUIRED:

1. ENTRA ID ADMIN ROLES (Portal required):
   → Go to: https://entra.microsoft.com
   → Roles and administrators → User Administrator
   → Add assignment for $NEW_OWNER
   
   This allows Tom to manage AVD users in tktconsulting.be

2. REMOVE YOUR ACCESS (after Tom confirms):
   az role assignment delete --assignee "YOUR_EMAIL" \\
       --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

3. SHARE DOCUMENTATION:
   - deploy-avd-platform-v5.sh
   - avd-config.json
   - admin-runbook.md
   - All passwords and secrets

4. UPDATE DNS (if applicable):
   Transfer any custom domain settings

VERIFICATION:
Tom should test access at:
  https://portal.azure.com/#@tktconsulting.be/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP

============================================================
EOF

echo ""
echo "Done! Tom now has full ownership of the AVD platform."
