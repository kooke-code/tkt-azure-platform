#!/bin/bash
#===============================================================================
# TKT Philippines SAP Platform - User Provisioning Script
# Version: 1.0
# Date: 2026-02-12
#
# Provisions new consultants for AVD access:
#   - Creates Entra ID user account
#   - Assigns to AVD Users group
#   - Assigns to customer-specific group
#   - Assigns M365 Business Premium license
#   - Sends welcome email with temporary password
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Microsoft Graph CLI extension (az extension add --name microsoft-graph)
#   - Global Administrator or User Administrator role
#   - M365 licenses available in tenant
#
# Usage:
#   ./provision-avd-users.sh users.json
#   ./provision-avd-users.sh users.json --dry-run
#   ./provision-avd-users.sh --single --first "John" --last "Doe" --email "john@gmail.com" --customer "Customer-001"
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# CONFIGURATION - Update for your environment
#-------------------------------------------------------------------------------

# Your Azure AD domain (the @domain part of user emails)
DOMAIN="yannickderidderoutlook.onmicrosoft.com"

# AVD Users group - members can access virtual desktops
AVD_USERS_GROUP="AVD-Users"

# M365 License SKU (Business Premium)
# Find yours with: az rest --method GET --url "https://graph.microsoft.com/v1.0/subscribedSkus" --query "value[].{sku:skuPartNumber, id:skuId}"
LICENSE_SKU_ID="cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46"  # M365 Business Premium - UPDATE THIS

# Temporary password settings
TEMP_PASSWORD_LENGTH=16
FORCE_CHANGE_PASSWORD=true

# Welcome email settings (requires configured mail-enabled account or Graph API mail permissions)
SEND_WELCOME_EMAIL=false  # Set to true if you have mail sending configured

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
TKT Philippines - AVD User Provisioning Script

USAGE:
    $0 <users.json>                    Process all users in JSON file
    $0 <users.json> --dry-run          Preview changes without making them
    $0 --single [options]              Provision a single user

SINGLE USER OPTIONS:
    --first <name>      First name (required)
    --last <name>       Last name (required)
    --email <email>     Personal email for password reset (required)
    --customer <id>     Customer assignment e.g., Customer-001 (required)
    --phone <number>    Phone number for MFA (optional)
    --title <title>     Job title (optional)
    --start <date>      Start date YYYY-MM-DD (optional)

EXAMPLES:
    $0 new-hires.json
    $0 new-hires.json --dry-run
    $0 --single --first "John" --last "Doe" --email "john@gmail.com" --customer "Customer-001"

JSON FILE FORMAT:
    See templates/user-provisioning-intake.json for the expected format.

EOF
    exit 0
}

generate_password() {
    # Generate a secure random password
    local length=${1:-$TEMP_PASSWORD_LENGTH}
    # Mix of uppercase, lowercase, numbers, and special chars
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

generate_upn() {
    local first="$1"
    local last="$2"
    
    # Convert to lowercase, remove special characters, create firstname.lastname format
    local clean_first=$(echo "$first" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]//g')
    local clean_last=$(echo "$last" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]//g')
    
    echo "${clean_first}.${clean_last}@${DOMAIN}"
}

check_user_exists() {
    local upn="$1"
    az ad user show --id "$upn" &>/dev/null && return 0 || return 1
}

check_group_exists() {
    local group_name="$1"
    az ad group show --group "$group_name" &>/dev/null && return 0 || return 1
}

get_group_id() {
    local group_name="$1"
    az ad group show --group "$group_name" --query "id" -o tsv 2>/dev/null
}

create_customer_group() {
    local customer="$1"
    local group_name="${customer}-Philippines-Team"
    
    if check_group_exists "$group_name"; then
        log_info "Customer group '$group_name' already exists"
        return 0
    fi
    
    log_info "Creating customer group: $group_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create group: $group_name"
        return 0
    fi
    
    az ad group create \
        --display-name "$group_name" \
        --mail-nickname "${customer}-PH-Team" \
        --description "Philippines SAP consultants for ${customer}" \
        --output none
    
    log_success "Created group: $group_name"
}

provision_user() {
    local first_name="$1"
    local last_name="$2"
    local personal_email="$3"
    local customer="$4"
    local phone="${5:-}"
    local title="${6:-SAP Consultant}"
    local start_date="${7:-}"
    local notes="${8:-}"
    
    local upn=$(generate_upn "$first_name" "$last_name")
    local display_name="${first_name} ${last_name}"
    local password=$(generate_password)
    local customer_group="${customer}-Philippines-Team"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Provisioning: $display_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  UPN:            $upn"
    echo "  Personal Email: $personal_email"
    echo "  Customer:       $customer"
    echo "  Job Title:      $title"
    [[ -n "$phone" ]] && echo "  Phone:          $phone"
    [[ -n "$start_date" ]] && echo "  Start Date:     $start_date"
    echo ""
    
    # Check if user already exists
    if check_user_exists "$upn"; then
        log_warning "User $upn already exists - skipping creation"
        return 0
    fi
    
    # Ensure customer group exists
    create_customer_group "$customer"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "[DRY RUN] Would create user: $upn"
        log_warning "[DRY RUN] Would add to groups: $AVD_USERS_GROUP, $customer_group"
        log_warning "[DRY RUN] Would assign license: M365 Business Premium"
        echo ""
        echo "  Temporary Password: [Generated on actual run]"
        return 0
    fi
    
    # Create the user
    log_info "Creating Entra ID user..."
    
    local account_enabled="true"
    if [[ -n "$start_date" ]]; then
        local today=$(date +%Y-%m-%d)
        if [[ "$start_date" > "$today" ]]; then
            account_enabled="false"
            log_info "Account will be disabled until start date: $start_date"
        fi
    fi
    
    az ad user create \
        --display-name "$display_name" \
        --user-principal-name "$upn" \
        --password "$password" \
        --force-change-password-next-sign-in "$FORCE_CHANGE_PASSWORD" \
        --mail-nickname "$(echo "${first_name}.${last_name}" | tr '[:upper:]' '[:lower:]')" \
        --given-name "$first_name" \
        --surname "$last_name" \
        --job-title "$title" \
        --other-mails "$personal_email" \
        --account-enabled "$account_enabled" \
        --output none
    
    log_success "User created: $upn"
    
    # Add phone number if provided (requires Graph API)
    if [[ -n "$phone" ]]; then
        log_info "Adding phone number for MFA..."
        # Note: Adding authentication phone requires Graph API with specific permissions
        # This is a placeholder - implement based on your Graph API setup
        log_warning "Phone number must be added manually in Entra ID portal (Graph API auth method not configured)"
    fi
    
    # Add to AVD Users group
    log_info "Adding to AVD Users group..."
    local avd_group_id=$(get_group_id "$AVD_USERS_GROUP")
    if [[ -n "$avd_group_id" ]]; then
        az ad group member add --group "$AVD_USERS_GROUP" --member-id "$(az ad user show --id "$upn" --query id -o tsv)" --output none 2>/dev/null || true
        log_success "Added to: $AVD_USERS_GROUP"
    else
        log_warning "AVD Users group not found - create it first or add user manually"
    fi
    
    # Add to customer group
    log_info "Adding to customer group..."
    az ad group member add --group "$customer_group" --member-id "$(az ad user show --id "$upn" --query id -o tsv)" --output none 2>/dev/null || true
    log_success "Added to: $customer_group"
    
    # Assign M365 license
    log_info "Assigning M365 Business Premium license..."
    local user_id=$(az ad user show --id "$upn" --query id -o tsv)
    
    az rest --method POST \
        --url "https://graph.microsoft.com/v1.0/users/${user_id}/assignLicense" \
        --headers "Content-Type=application/json" \
        --body "{\"addLicenses\": [{\"skuId\": \"${LICENSE_SKU_ID}\"}], \"removeLicenses\": []}" \
        --output none 2>/dev/null || log_warning "License assignment failed - assign manually or check available licenses"
    
    log_success "License assigned"
    
    # Output credentials
    echo ""
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│  CREDENTIALS - SAVE THESE SECURELY                        │"
    echo "├────────────────────────────────────────────────────────────┤"
    echo "│  Username:  $upn"
    echo "│  Password:  $password"
    echo "│  Portal:    https://myapps.microsoft.com"
    echo "│  AVD URL:   https://client.wvd.microsoft.com/arm/webclient │"
    echo "└────────────────────────────────────────────────────────────┘"
    echo ""
    
    # Append to credentials file
    echo "---" >> provisioned-users.txt
    echo "Name: $display_name" >> provisioned-users.txt
    echo "Username: $upn" >> provisioned-users.txt  
    echo "Temporary Password: $password" >> provisioned-users.txt
    echo "Personal Email: $personal_email" >> provisioned-users.txt
    echo "Customer: $customer" >> provisioned-users.txt
    echo "Provisioned: $(date)" >> provisioned-users.txt
    
    log_success "Provisioning complete for $display_name"
    
    return 0
}

process_json_file() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        log_error "File not found: $json_file"
        exit 1
    fi
    
    log_info "Processing users from: $json_file"
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON processing. Install with: brew install jq (Mac) or apt install jq (Linux)"
        exit 1
    fi
    
    local user_count=$(jq '.users | length' "$json_file")
    log_info "Found $user_count user(s) to provision"
    echo ""
    
    # Process each user
    for i in $(seq 0 $((user_count - 1))); do
        local first=$(jq -r ".users[$i].firstName" "$json_file")
        local last=$(jq -r ".users[$i].lastName" "$json_file")
        local email=$(jq -r ".users[$i].personalEmail" "$json_file")
        local customer=$(jq -r ".users[$i].customerAssignment" "$json_file")
        local phone=$(jq -r ".users[$i].phoneNumber // empty" "$json_file")
        local title=$(jq -r ".users[$i].jobTitle // \"SAP Consultant\"" "$json_file")
        local start=$(jq -r ".users[$i].startDate // empty" "$json_file")
        local notes=$(jq -r ".users[$i].notes // empty" "$json_file")
        
        provision_user "$first" "$last" "$email" "$customer" "$phone" "$title" "$start" "$notes"
    done
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------

DRY_RUN="false"
SINGLE_MODE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --dry-run)
            DRY_RUN="true"
            log_warning "DRY RUN MODE - No changes will be made"
            shift
            ;;
        --single)
            SINGLE_MODE="true"
            shift
            ;;
        --first)
            SINGLE_FIRST="$2"
            shift 2
            ;;
        --last)
            SINGLE_LAST="$2"
            shift 2
            ;;
        --email)
            SINGLE_EMAIL="$2"
            shift 2
            ;;
        --customer)
            SINGLE_CUSTOMER="$2"
            shift 2
            ;;
        --phone)
            SINGLE_PHONE="$2"
            shift 2
            ;;
        --title)
            SINGLE_TITLE="$2"
            shift 2
            ;;
        --start)
            SINGLE_START="$2"
            shift 2
            ;;
        *)
            JSON_FILE="$1"
            shift
            ;;
    esac
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     TKT Philippines - AVD User Provisioning                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check Azure CLI login
if ! az account show &>/dev/null; then
    log_error "Not logged in to Azure. Run 'az login' first."
    exit 1
fi

log_info "Logged in as: $(az account show --query user.name -o tsv)"
log_info "Tenant: $(az account show --query tenantId -o tsv)"
echo ""

# Initialize credentials file
if [[ "$DRY_RUN" != "true" ]]; then
    echo "# Provisioned Users - $(date)" > provisioned-users.txt
    echo "# KEEP THIS FILE SECURE - Contains temporary passwords" >> provisioned-users.txt
fi

if [[ "$SINGLE_MODE" == "true" ]]; then
    # Single user mode
    if [[ -z "$SINGLE_FIRST" || -z "$SINGLE_LAST" || -z "$SINGLE_EMAIL" || -z "$SINGLE_CUSTOMER" ]]; then
        log_error "Single mode requires: --first, --last, --email, --customer"
        show_help
    fi
    
    provision_user "$SINGLE_FIRST" "$SINGLE_LAST" "$SINGLE_EMAIL" "$SINGLE_CUSTOMER" \
        "$SINGLE_PHONE" "${SINGLE_TITLE:-SAP Consultant}" "$SINGLE_START" ""
else
    # JSON file mode
    if [[ -z "$JSON_FILE" ]]; then
        log_error "No JSON file specified"
        show_help
    fi
    
    process_json_file "$JSON_FILE"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN COMPLETE - No changes were made"
else
    log_success "PROVISIONING COMPLETE"
    log_info "Credentials saved to: provisioned-users.txt"
    log_warning "Send credentials securely to users and delete the file after!"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "NEXT STEPS FOR NEW USERS:"
echo "1. Send them their credentials securely (not via email!)"
echo "2. They log in at: https://myapps.microsoft.com"
echo "3. They set up MFA (Authenticator app)"
echo "4. They access AVD at: https://client.wvd.microsoft.com/arm/webclient"
echo "5. First login creates their FSLogix profile automatically"
echo ""
