terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 4.0"
    }
  }
}

module "naming" {
  source  = "Azure/naming/azurerm"
  prefix = [ "todolist" ]
}

variable "context" {
  description = "Context variable set by Radius which includes the Radius Application, Environment, and other Radius properties"
  type = any
}

variable "resource_group_name" {
  description = "Azure Resource group set via a parameter on the Radius Recipe"
  type = string
}

variable "location" {
  description = "Azure region set via a parameter on the Radius Recipe"
  type = string
}

variable "size_sku_map" {
  type = map(string)
  default = {
    S = "GP_Standard_D2ds_v5"
    M = "GP_Standard_D4ds_v5"
    L = "GP_Standard_D8ds_v5"
    XL = "GP_Standard_D16ds_v5"
  }
}

resource "random_password" "password" {
  length           = 16
}

locals {
  storage_mb = var.context.resource.properties.storage_gb == "" ? 32768 : var.context.resource.properties.storage_gb * 1024
}

resource "azurerm_postgresql_flexible_server" "todolist-db" {
  name                = module.naming.postgresql_database.name_unique
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login          = "postgres"
  administrator_password       = random_password.password.result

  sku_name   = var.size_sku_map[var.context.resource.properties.size]
  storage_mb = local.storage_mb
  version    = "16"

  zone = "1"
}

# Set require_ssl to off
resource "azurerm_postgresql_flexible_server_configuration" "disable_ssl" {
  name                = "require_secure_transport"
  server_id           = azurerm_postgresql_flexible_server.todolist-db.id
  value               = "off"
}

// Create server firewall rules for azure service internal access
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_access" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_postgresql_flexible_server.todolist-db.id
  start_ip_address = "0.0.0.0" // IP address of azure services
  end_ip_address   = "0.0.0.0"
}

output "result" {
  value = {
    values = {
      host = azurerm_postgresql_flexible_server.todolist-db.fqdn
      port = "5432"
      database = "postgres"
      username = "postgres"
      password = random_password.password.result
    }
  }
}