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