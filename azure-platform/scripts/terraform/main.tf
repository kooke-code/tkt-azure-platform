#===============================================================================
# TKT Philippines SAP Platform - Azure Firewall Terraform Configuration
# Version: 1.0
# Date: 2026-01-30
#
# This Terraform configuration deploys Azure Firewall with URL filtering.
#
# Usage:
#   terraform init
#   terraform plan -var="customer_number=001"
#   terraform apply -var="customer_number=001"
#===============================================================================

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#-------------------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------------------

variable "customer_number" {
  description = "Customer identifier (e.g., 001, 002)"
  type        = string
  default     = "001"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "southeastasia"
}

variable "workstation_subnet_prefix" {
  description = "Address prefix for workstation subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "firewall_subnet_prefix" {
  description = "Address prefix for Azure Firewall subnet"
  type        = string
  default     = "10.1.2.0/26"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

#-------------------------------------------------------------------------------
# Locals
#-------------------------------------------------------------------------------

locals {
  resource_group_name  = "rg-customer-${var.customer_number}-philippines"
  vnet_name            = "vnet-customer-${var.customer_number}-ph"
  firewall_name        = "afw-customer-${var.customer_number}-ph"
  firewall_pip_name    = "pip-afw-customer-${var.customer_number}-ph"
  firewall_policy_name = "afwp-customer-${var.customer_number}-ph"
  route_table_name     = "rt-customer-${var.customer_number}-ph"
  
  default_tags = {
    Customer    = "Customer-${var.customer_number}"
    Environment = "Production"
    Project     = "SAP-Consulting"
    CostCenter  = "Customer-${var.customer_number}-Philippines"
    ManagedBy   = "Terraform"
  }
  
  all_tags = merge(local.default_tags, var.tags)
}

#-------------------------------------------------------------------------------
# Data Sources
#-------------------------------------------------------------------------------

data "azurerm_resource_group" "main" {
  name = local.resource_group_name
}

data "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  resource_group_name = data.azurerm_resource_group.main.name
}

data "azurerm_log_analytics_workspace" "main" {
  name                = "law-tkt-customer${var.customer_number}-sea"
  resource_group_name = data.azurerm_resource_group.main.name
}

#-------------------------------------------------------------------------------
# Azure Firewall Subnet
#-------------------------------------------------------------------------------

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = data.azurerm_virtual_network.main.name
  address_prefixes     = [var.firewall_subnet_prefix]
}

#-------------------------------------------------------------------------------
# Public IP for Firewall
#-------------------------------------------------------------------------------

resource "azurerm_public_ip" "firewall" {
  name                = local.firewall_pip_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.all_tags
}

#-------------------------------------------------------------------------------
# Firewall Policy
#-------------------------------------------------------------------------------

resource "azurerm_firewall_policy" "main" {
  name                = local.firewall_policy_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = local.all_tags
}

#-------------------------------------------------------------------------------
# Firewall Policy Rule Collection Group - Application Rules
#-------------------------------------------------------------------------------

resource "azurerm_firewall_policy_rule_collection_group" "application" {
  name               = "DefaultApplicationRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100

  # SAP Cloud Services
  application_rule_collection {
    name     = "Allow-SAP-Cloud"
    priority = 100
    action   = "Allow"

    rule {
      name = "SAP-Domains"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = [var.workstation_subnet_prefix]
      destination_fqdns = [
        "*.sap.com",
        "*.sapcloud.com",
        "*.hana.ondemand.com",
        "*.s4hana.cloud.sap",
        "*.successfactors.com",
        "*.ariba.com",
        "*.concur.com"
      ]
    }
  }

  # Microsoft Services
  application_rule_collection {
    name     = "Allow-Microsoft-Services"
    priority = 200
    action   = "Allow"

    rule {
      name = "Microsoft-Domains"
      protocols {
        type = "Https"
        port = 443
      }
      source_addresses = [var.workstation_subnet_prefix]
      destination_fqdns = [
        "*.microsoft.com",
        "*.microsoftonline.com",
        "*.azure.com",
        "*.azure.net",
        "*.windows.net",
        "*.office.com",
        "*.office365.com",
        "*.sharepoint.com",
        "*.teams.microsoft.com",
        "*.live.com",
        "*.msauth.net",
        "*.msftauth.net",
        "*.msauthimages.net",
        "*.msecnd.net",
        "*.msocdn.com"
      ]
    }
  }

  # Windows Update
  application_rule_collection {
    name     = "Allow-Windows-Update"
    priority = 300
    action   = "Allow"

    rule {
      name = "WindowsUpdate-Domains"
      protocols {
        type = "Https"
        port = 443
      }
      protocols {
        type = "Http"
        port = 80
      }
      source_addresses = [var.workstation_subnet_prefix]
      destination_fqdns = [
        "*.windowsupdate.com",
        "*.update.microsoft.com",
        "*.windowsupdate.microsoft.com",
        "*.download.windowsupdate.com",
        "*.ntservicepack.microsoft.com"
      ]
    }
  }
}

#-------------------------------------------------------------------------------
# Firewall Policy Rule Collection Group - Network Rules
#-------------------------------------------------------------------------------

resource "azurerm_firewall_policy_rule_collection_group" "network" {
  name               = "DefaultNetworkRuleCollectionGroup"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 200

  network_rule_collection {
    name     = "Allow-DNS"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "DNS-Outbound"
      protocols             = ["UDP"]
      source_addresses      = [var.workstation_subnet_prefix]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }

  network_rule_collection {
    name     = "Allow-NTP"
    priority = 110
    action   = "Allow"

    rule {
      name                  = "NTP-Outbound"
      protocols             = ["UDP"]
      source_addresses      = [var.workstation_subnet_prefix]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }
}

#-------------------------------------------------------------------------------
# Azure Firewall
#-------------------------------------------------------------------------------

resource "azurerm_firewall" "main" {
  name                = local.firewall_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.main.id
  tags                = local.all_tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

#-------------------------------------------------------------------------------
# Route Table
#-------------------------------------------------------------------------------

resource "azurerm_route_table" "main" {
  name                          = local.route_table_name
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.main.name
  disable_bgp_route_propagation = true
  tags                          = local.all_tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }
}

#-------------------------------------------------------------------------------
# Associate Route Table with Workstation Subnet
#-------------------------------------------------------------------------------

resource "azurerm_subnet_route_table_association" "workstations" {
  subnet_id      = "${data.azurerm_virtual_network.main.id}/subnets/snet-workstations"
  route_table_id = azurerm_route_table.main.id
}

#-------------------------------------------------------------------------------
# Diagnostic Settings
#-------------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "FirewallDiagnostics"
  target_resource_id         = azurerm_firewall.main.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AzureFirewallApplicationRule"
  }

  enabled_log {
    category = "AzureFirewallNetworkRule"
  }

  enabled_log {
    category = "AzureFirewallDnsProxy"
  }

  metric {
    category = "AllMetrics"
  }
}

#-------------------------------------------------------------------------------
# Outputs
#-------------------------------------------------------------------------------

output "firewall_private_ip" {
  description = "Private IP address of the Azure Firewall"
  value       = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Public IP address of the Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_id" {
  description = "Resource ID of the Azure Firewall"
  value       = azurerm_firewall.main.id
}

output "route_table_id" {
  description = "Resource ID of the route table"
  value       = azurerm_route_table.main.id
}
