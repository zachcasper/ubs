terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

variable "context" {
  description = "This variable contains Radius recipe context."
  type = any
}

data "azurerm_resource_group" "radius_provided-rg" {
  name = var.context.azure.resourceGroup
}

resource "random_password" "password" {
  length           = 16
}

resource "azurerm_postgresql_server" "todolist-db" {
  name                = "todolist-db"
  location            = data.azurerm_resource_group.radius_provided-rg.location
  resource_group_name = data.azurerm_resource_group.radius_provided-rg.name

  administrator_login          = "postgres"
  administrator_login_password = random_password.password.result

  sku_name   = "GP_Gen5_4"
  version    = "11"

  ssl_enforcement_enabled          = true
  ssl_minimal_tls_version_enforced = "TLS1_2"
}

output "result" {
  value = {
    values = {
      host = azurerm_postgresql_server.server.fqdn
      port = "5432"
      database = "postgres_db"
      username = "postgres"
      password = random_password.password.result
    }
  }
}