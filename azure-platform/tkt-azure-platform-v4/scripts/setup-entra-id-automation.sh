#!/bin/bash
#===============================================================================
# TKT Philippines AVD Platform - Entra ID Automation Script
# Version: 4.0
# Date: 2026-02-12
#
# DESCRIPTION:
#   Automates Entra ID (Azure AD) configuration including:
#   - Create consultant user accounts
#   - Create security group for AVD users
#   - Assign users to security group
#   - Assign M365 Business Premium licenses
#   - Create Conditional Access policy (require MFA for AVD)
#   - Assign security group to AVD application group
#
# PREREQUISITES:
#   - Azure CLI authenticated
#   - Global Administrator or User Administrator role
#   - Privileged Role Administrator (for Conditional Access)
#   - Available M365 Business Premium licenses
#
# USAGE:
#   ./setup-entra-id-automation.sh \
#     --domain yourcompany.onmicrosoft.com \
#     --user-prefix ph-consultant \
#     --user-count 4 \
#     --password "TempPass123!" \
#     --security-group TKT-Philippines-AVD-Users \
#     --appgroup-name tktph-dag \
#     --resource-group rg-tktph-avd-prod-sea \
#     --credentials-file /tmp/credentials.txt
#===============================================================================

set -o errexit
set -o pipefail
set -o nounset

#===============================================================================
# CONFIGURATION
#===============================================================================

ENTRA_DOMAIN=""
USER_PREFIX=""
USER_COUNT=""
USER_PASSWORD=""
SECURITY_GROUP_NAME=""
APPGROUP_NAME=""
RESOURCE_GROUP=""
CREDENTIALS_FILE=""
M365_LICENSE_SKU="${M365_LICENSE_SKU:-O365_BUSINESS_PREMIUM}"

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
        INFO)   echo -e "${BLUE}[$timestamp] [ENTRA] [INFO]${NC} $message" ;;
        SUCCESS)echo -e "${GREEN}[$timestamp] [ENTRA] [SUCCESS]${NC} ✓ $message" ;;
        WARN)   echo -e "${YELLOW}[$timestamp] [ENTRA] [WARNING]${NC} ⚠ $message" ;;
        ERROR)  echo -e "${RED}[$timestamp] [ENTRA] [ERROR]${NC} ✗ $message" ;;
    esac
}

#===============================================================================
# USER CREATION
#===============================================================================

create_user() {
    local user_number="$1"
    local display_name="PH Consultant $(printf '%03d' $user_number)"
    local user_principal_name="${USER_PREFIX}-$(printf '%03d' $user_number)@${ENTRA_DOMAIN}"
    local mail_nickname="${USER_PREFIX}-$(printf '%03d' $user_number)"
    
    log INFO "Creating user: $user_principal_name"
    
    # Check if user exists
    if az ad user show --id "$user_principal_name" &>/dev/null; then
        log INFO "User $user_principal_name already exists"
        return 0
    fi
    
    # Create user via Graph API (az ad user create)
    az ad user create \
        --display-name "$display_name" \
        --user-principal-name "$user_principal_name" \
        --password "$USER_PASSWORD" \
        --force-change-password-next-sign-in true \
        --mail-nickname "$mail_nickname" \
        --output none 2>/dev/null || {
            log WARN "Failed to create user via az ad - trying alternative method"
            
            # Alternative: Use Graph API directly
            local user_json=$(cat << EOF
{
    "accountEnabled": true,
    "displayName": "$display_name",
    "mailNickname": "$mail_nickname",
    "userPrincipalName": "$user_principal_name",
    "passwordProfile": {
        "forceChangePasswordNextSignIn": true,
        "password": "$USER_PASSWORD"
    }
}
EOF
)
            az rest --method POST \
                --url "https://graph.microsoft.com/v1.0/users" \
                --body "$user_json" \
                --output none 2>/dev/null || {
                    log ERROR "Failed to create user: $user_principal_name"
                    return 1
                }
        }
    
    # Save credentials
    echo "User: $user_principal_name" >> "$CREDENTIALS_FILE"
    echo "Password: $USER_PASSWORD (temporary - must change on first login)" >> "$CREDENTIALS_FILE"
    echo "---" >> "$CREDENTIALS_FILE"
    
    log SUCCESS "Created user: $user_principal_name"
    return 0
}

#===============================================================================
# SECURITY GROUP
#===============================================================================

create_security_group() {
    log INFO "Creating security group: $SECURITY_GROUP_NAME"
    
    # Check if group exists
    local group_id=$(az ad group show --group "$SECURITY_GROUP_NAME" --query "id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$group_id" ]]; then
        log INFO "Security group already exists: $group_id"
        echo "$group_id"
        return 0
    fi
    
    # Create group
    group_id=$(az ad group create \
        --display-name "$SECURITY_GROUP_NAME" \
        --mail-nickname "$(echo $SECURITY_GROUP_NAME | tr ' ' '-' | tr '[:upper:]' '[:lower:]')" \
        --description "TKT Philippines AVD users - SAP consultants" \
        --query "id" -o tsv)
    
    log SUCCESS "Created security group: $SECURITY_GROUP_NAME ($group_id)"
    echo "$group_id"
}

add_users_to_group() {
    local group_id="$1"
    
    log INFO "Adding users to security group..."
    
    for i in $(seq 1 "$USER_COUNT"); do
        local user_principal_name="${USER_PREFIX}-$(printf '%03d' $i)@${ENTRA_DOMAIN}"
        
        # Get user ID
        local user_id=$(az ad user show --id "$user_principal_name" --query "id" -o tsv 2>/dev/null || echo "")
        
        if [[ -z "$user_id" ]]; then
            log WARN "User not found: $user_principal_name"
            continue
        fi
        
        # Check if already member
        if az ad group member check --group "$group_id" --member-id "$user_id" --query "value" -o tsv 2>/dev/null | grep -q "true"; then
            log INFO "User already in group: $user_principal_name"
            continue
        fi
        
        # Add to group
        az ad group member add --group "$group_id" --member-id "$user_id" --output none 2>/dev/null || {
            log WARN "Failed to add user to group: $user_principal_name"
            continue
        }
        
        log SUCCESS "Added to group: $user_principal_name"
    done
}

#===============================================================================
# LICENSE ASSIGNMENT
#===============================================================================

assign_licenses() {
    log INFO "Assigning M365 Business Premium licenses..."
    
    # Get available license SKUs
    local sku_id=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/subscribedSkus" \
        --query "value[?contains(skuPartNumber, 'BUSINESS_PREMIUM') || contains(skuPartNumber, 'O365_BUSINESS_PREMIUM')].skuId | [0]" \
        -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$sku_id" ]]; then
        log WARN "M365 Business Premium license SKU not found. Available SKUs:"
        az rest --method GET \
            --url "https://graph.microsoft.com/v1.0/subscribedSkus" \
            --query "value[].{sku:skuPartNumber, available:prepaidUnits.enabled, consumed:consumedUnits}" \
            -o table 2>/dev/null || log WARN "Could not list SKUs"
        return 1
    fi
    
    log INFO "Found license SKU: $sku_id"
    
    for i in $(seq 1 "$USER_COUNT"); do
        local user_principal_name="${USER_PREFIX}-$(printf '%03d' $i)@${ENTRA_DOMAIN}"
        
        # Get user ID
        local user_id=$(az ad user show --id "$user_principal_name" --query "id" -o tsv 2>/dev/null || echo "")
        
        if [[ -z "$user_id" ]]; then
            log WARN "User not found for license assignment: $user_principal_name"
            continue
        fi
        
        # Check current licenses
        local has_license=$(az rest --method GET \
            --url "https://graph.microsoft.com/v1.0/users/$user_id/licenseDetails" \
            --query "value[?skuId=='$sku_id'] | length(@)" \
            -o tsv 2>/dev/null || echo "0")
        
        if [[ "$has_license" != "0" ]]; then
            log INFO "User already has license: $user_principal_name"
            continue
        fi
        
        # Assign license
        local license_json=$(cat << EOF
{
    "addLicenses": [
        {
            "skuId": "$sku_id"
        }
    ],
    "removeLicenses": []
}
EOF
)
        
        az rest --method POST \
            --url "https://graph.microsoft.com/v1.0/users/$user_id/assignLicense" \
            --body "$license_json" \
            --output none 2>/dev/null || {
                log WARN "Failed to assign license to: $user_principal_name"
                continue
            }
        
        log SUCCESS "License assigned to: $user_principal_name"
    done
}

#===============================================================================
# CONDITIONAL ACCESS POLICY
#===============================================================================

create_conditional_access_policy() {
    local group_id="$1"
    local policy_name="TKT-AVD-Require-MFA"
    
    log INFO "Creating Conditional Access policy: $policy_name"
    
    # Check if policy exists
    local existing_policy=$(az rest --method GET \
        --url "https://graph.microsoft.com/v1.0/identity/conditionalAccessPolicies" \
        --query "value[?displayName=='$policy_name'].id | [0]" \
        -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$existing_policy" ]]; then
        log INFO "Conditional Access policy already exists: $existing_policy"
        return 0
    fi
    
    # Create policy
    local policy_json=$(cat << EOF
{
    "displayName": "$policy_name",
    "state": "enabled",
    "conditions": {
        "clientAppTypes": ["all"],
        "applications": {
            "includeApplications": ["9cdead84-a844-4324-93f2-b2e6bb768d07"]
        },
        "users": {
            "includeGroups": ["$group_id"]
        }
    },
    "grantControls": {
        "operator": "OR",
        "builtInControls": ["mfa"]
    }
}
EOF
)
    
    # Note: 9cdead84-a844-4324-93f2-b2e6bb768d07 is the AVD client app ID
    
    az rest --method POST \
        --url "https://graph.microsoft.com/v1.0/identity/conditionalAccessPolicies" \
        --body "$policy_json" \
        --output none 2>/dev/null || {
            log WARN "Failed to create Conditional Access policy"
            log WARN "You may need to create this manually in the Entra portal"
            log WARN "Policy settings: Require MFA for AVD access, target group: $SECURITY_GROUP_NAME"
            return 1
        }
    
    log SUCCESS "Conditional Access policy created: $policy_name"
}

#===============================================================================
# AVD APPLICATION GROUP ASSIGNMENT
#===============================================================================

assign_group_to_appgroup() {
    local group_id="$1"
    
    log INFO "Assigning security group to AVD application group..."
    
    # Get application group resource ID
    local appgroup_id=$(az desktopvirtualization applicationgroup show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APPGROUP_NAME" \
        --query "id" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$appgroup_id" ]]; then
        log ERROR "Application group not found: $APPGROUP_NAME"
        return 1
    fi
    
    # Assign role (Desktop Virtualization User)
    az role assignment create \
        --assignee-object-id "$group_id" \
        --assignee-principal-type Group \
        --role "Desktop Virtualization User" \
        --scope "$appgroup_id" \
        --output none 2>/dev/null || {
            # Check if already assigned
            local existing=$(az role assignment list \
                --assignee "$group_id" \
                --scope "$appgroup_id" \
                --query "[?roleDefinitionName=='Desktop Virtualization User'] | length(@)" \
                -o tsv 2>/dev/null || echo "0")
            
            if [[ "$existing" != "0" ]]; then
                log INFO "Role assignment already exists"
            else
                log WARN "Failed to create role assignment"
                return 1
            fi
        }
    
    log SUCCESS "Security group assigned to application group"
}

#===============================================================================
# ARGUMENT PARSING
#===============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                ENTRA_DOMAIN="$2"
                shift 2
                ;;
            --user-prefix)
                USER_PREFIX="$2"
                shift 2
                ;;
            --user-count)
                USER_COUNT="$2"
                shift 2
                ;;
            --password)
                USER_PASSWORD="$2"
                shift 2
                ;;
            --security-group)
                SECURITY_GROUP_NAME="$2"
                shift 2
                ;;
            --appgroup-name)
                APPGROUP_NAME="$2"
                shift 2
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --credentials-file)
                CREDENTIALS_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --domain NAME           Entra ID domain (e.g., company.onmicrosoft.com)"
                echo "  --user-prefix PREFIX    User principal name prefix"
                echo "  --user-count N          Number of users to create"
                echo "  --password PASS         Temporary password for users"
                echo "  --security-group NAME   Security group name"
                echo "  --appgroup-name NAME    AVD application group name"
                echo "  --resource-group NAME   Resource group containing AVD"
                echo "  --credentials-file PATH Output file for credentials"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    local required_args=("ENTRA_DOMAIN" "USER_PREFIX" "USER_COUNT" "USER_PASSWORD" 
                         "SECURITY_GROUP_NAME" "APPGROUP_NAME" "RESOURCE_GROUP" "CREDENTIALS_FILE")
    
    for arg in "${required_args[@]}"; do
        if [[ -z "${!arg}" ]]; then
            log ERROR "Missing required argument: --$(echo $arg | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
            exit 1
        fi
    done
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    parse_arguments "$@"
    
    log INFO "Starting Entra ID automation..."
    log INFO "Domain: $ENTRA_DOMAIN"
    log INFO "User prefix: $USER_PREFIX"
    log INFO "User count: $USER_COUNT"
    log INFO "Security group: $SECURITY_GROUP_NAME"
    
    # Initialize credentials file
    echo "# TKT Philippines AVD User Credentials" > "$CREDENTIALS_FILE"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$CREDENTIALS_FILE"
    echo "# IMPORTANT: Users must change password on first login" >> "$CREDENTIALS_FILE"
    echo "---" >> "$CREDENTIALS_FILE"
    
    # Create users
    for i in $(seq 1 "$USER_COUNT"); do
        create_user "$i" || true
    done
    
    # Create security group
    local group_id=$(create_security_group)
    
    if [[ -z "$group_id" ]]; then
        log ERROR "Failed to create security group"
        exit 1
    fi
    
    # Add users to group
    add_users_to_group "$group_id"
    
    # Assign licenses
    assign_licenses || log WARN "License assignment had issues - may need manual verification"
    
    # Create Conditional Access policy
    create_conditional_access_policy "$group_id" || log WARN "Conditional Access policy may need manual creation"
    
    # Assign group to AVD application group
    assign_group_to_appgroup "$group_id" || log WARN "Application group assignment may need manual verification"
    
    # Set credentials file permissions
    chmod 600 "$CREDENTIALS_FILE"
    
    log SUCCESS "Entra ID automation complete"
    log INFO "Credentials saved to: $CREDENTIALS_FILE"
}

main "$@"
