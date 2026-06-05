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

# Custom provider — loads schemas/schema.naming.json from the module root.
# Contains resource types absent from azure/caf (e.g. azurerm_monitor_alert_processing_rule_suppression).
# path is relative to the process working directory (module root when running tofu test).
provider "standesamt" {
  alias = "custom"
  schema_reference = {
    custom_url = "./schemas"
  }
  environment = "test"
  separator   = "-"
  convention  = "default"
}

data "standesamt_config" "this" {}

data "standesamt_config" "custom" {
  provider = standesamt.custom
}

output "naming_configuration" {
  value = {
    configuration = data.standesamt_config.this.configuration
    locations     = {}
    schema        = data.standesamt_config.this.schema
  }
}

output "naming_configuration_custom" {
  value = {
    configuration = data.standesamt_config.custom.configuration
    locations     = {}
    schema        = data.standesamt_config.custom.schema
  }
}
