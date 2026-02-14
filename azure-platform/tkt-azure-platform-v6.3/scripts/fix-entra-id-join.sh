#!/bin/bash
#===============================================================================
# Fix AVD Session Hosts - Enable Entra ID Join
# 
# Problem: VMs created without Entra ID join, showing "DomainJoinedCheck" failed
# Solution: Add AADLoginForWindows extension to enable Entra ID join
#
# For Entra ID-joined AVD (no on-premises AD), session hosts must have:
# 1. AADLoginForWindows extension installed
# 2. System-assigned managed identity enabled
# 3. Users with "Virtual Machine User Login" role on VMs
#===============================================================================

set -o errexit
set -o pipefail

RESOURCE_GROUP="${1:-rg-tktph-avd-prod-sea}"
SECURITY_GROUP="TKT-Philippines-AVD-Users"

echo "============================================================"
echo "  Fix AVD Session Hosts - Enable Entra ID Join"
echo "============================================================"
echo ""
echo "  Resource Group: $RESOURCE_GROUP"
echo ""

# Get subscription ID
SUB_ID=$(az account show --query id -o tsv)

# List VMs
echo "[1/4] Finding session host VMs..."
VMS=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
echo "  Found: $VMS"
echo ""

# Enable system-assigned managed identity and install AAD extension
for VM in $VMS; do
    echo "[2/4] Configuring $VM for Entra ID join..."
    
    # Enable system-assigned managed identity
    echo "  → Enabling managed identity..."
    az vm identity assign \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM" \
        --output none 2>/dev/null || echo "    (may already be enabled)"
    
    # Check if AADLoginForWindows extension exists
    EXISTING=$(az vm extension show \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$VM" \
        --name "AADLoginForWindows" \
        --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$EXISTING" == "Succeeded" ]]; then
        echo "  → AADLoginForWindows already installed"
    else
        echo "  → Installing AADLoginForWindows extension..."
        az vm extension set \
            --resource-group "$RESOURCE_GROUP" \
            --vm-name "$VM" \
            --name "AADLoginForWindows" \
            --publisher "Microsoft.Azure.ActiveDirectory" \
            --version "2.0" \
            --output none
        echo "  ✓ AADLoginForWindows installed on $VM"
    fi
    echo ""
done

# Assign VM User Login role to security group
echo "[3/4] Assigning Virtual Machine User Login role..."

GROUP_ID=$(az ad group show --group "$SECURITY_GROUP" --query id -o tsv 2>/dev/null || echo "")

if [[ -z "$GROUP_ID" ]]; then
    echo "  ⚠ Security group '$SECURITY_GROUP' not found"
    echo "  Creating it now..."
    GROUP_ID=$(az ad group create \
        --display-name "$SECURITY_GROUP" \
        --mail-nickname "tktph-avd-users" \
        --query id -o tsv)
fi

for VM in $VMS; do
    VM_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM" --query id -o tsv)
    
    # Check if role already assigned
    EXISTING_ROLE=$(az role assignment list \
        --scope "$VM_ID" \
        --assignee "$GROUP_ID" \
        --role "Virtual Machine User Login" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_ROLE" ]]; then
        echo "  → $VM: Role already assigned"
    else
        az role assignment create \
            --assignee "$GROUP_ID" \
            --role "Virtual Machine User Login" \
            --scope "$VM_ID" \
            --output none 2>/dev/null || echo "  → $VM: Role assignment pending"
        echo "  ✓ $VM: Virtual Machine User Login assigned"
    fi
done
echo ""

# Restart VMs to apply changes
echo "[4/4] Restarting VMs to apply Entra ID join..."
for VM in $VMS; do
    echo "  → Restarting $VM..."
    az vm restart --resource-group "$RESOURCE_GROUP" --name "$VM" --no-wait
done

echo ""
echo "============================================================"
echo "  Entra ID Join Configuration Complete"
echo "============================================================"
echo ""
echo "  VMs are restarting. This takes 2-5 minutes."
echo ""
echo "  After restart, verify health:"
echo "    az desktopvirtualization sessionhost list \\"
echo "        --resource-group $RESOURCE_GROUP \\"
echo "        --host-pool-name tktph-hp \\"
echo "        --query \"[].{Name:name, Status:status}\" -o table"
echo ""
echo "  The DomainJoinedCheck should now pass (or be skipped for Entra ID join)."
echo ""
echo "  IMPORTANT: For Entra ID-joined AVD, users sign in with:"
echo "    Username: AzureAD\\user@tktconsulting.be"
echo "    or just: user@tktconsulting.be"
echo ""
