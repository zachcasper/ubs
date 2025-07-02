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
  description = "This variable contains Radius recipe context."
  type = any
}

resource "random_password" "password" {
  length           = 16
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

resource "azurerm_postgresql_flexible_server" "todolist-db" {
  name                = module.naming.postgresql_database.name_unique
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login          = "postgres"
  administrator_password = random_password.password.result

  sku_name   = "B_Standard_B1ms"
  version    = "16"

  zone = "1"
}

// Create server firewall rules for azure service internal access
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_access" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_postgresql_flexible_server.todolist-db.id
  start_ip_address = "0.0.0.0" // IP address of azure services
  end_ip_address   = "0.0.0.0"
}

// Create server firewall rules for allowed I.P addresses
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  name             = "AllowWorkstationIP"
  server_id        = azurerm_postgresql_flexible_server.todolist-db.id
  start_ip_address = "136.49.175.58"
  end_ip_address   = "136.49.175.58"
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