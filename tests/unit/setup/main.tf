terraform {
  required_providers {
    standesamt = {
      source  = "glueckkanja/standesamt"
      version = ">= 2.0.1, < 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.68.0, < 5.0"
    }
    modtm = {
      source  = "azure/modtm"
      version = ">= 0.3.5, < 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1, < 4.0"
    }
  }
}

provider "standesamt" {
  schema_reference = {
    path = "azure/caf"
    ref  = "2025.04"
  }
  environment = "test"
  separator   = "-"
  convention  = "default"
}

data "standesamt_config" "this" {}

output "naming_configuration" {
  value = {
    configuration = data.standesamt_config.this.configuration
    locations     = {}
    schema        = data.standesamt_config.this.schema
  }
}
