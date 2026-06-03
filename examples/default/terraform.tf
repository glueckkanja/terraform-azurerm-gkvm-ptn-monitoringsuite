terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.68.0, < 5.0"
    }
    standesamt = {
      source  = "glueckkanja/standesamt"
      version = ">= 2.0.1, < 3.0"
    }
    modtm = {
      source  = "azure/modtm"
      version = ">= 0.3.5, < 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1, < 4.0"
    }
    gkvm = {
      source  = "glueckkanja/gkvm"
      version = ">= 0.1.0, < 1.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "gkvm" {
  github_repo = "glueckkanja/gkvm-monitoring-defaults"
  github_ref  = "main"
  # github_token read from GH_TOKEN env var (gh CLI sets this automatically)
}

provider "standesamt" {
  schema_reference {
    path = "azure/caf"
    ref  = "2025.04"
  }
  environment = "prod"
  separator   = "-"
  convention  = "default"
}

# Custom provider — loads ../../schemas/schema.naming.json (relative to examples/default working dir).
# Contains resource types absent from azure/caf (e.g. azurerm_monitor_alert_processing_rule_suppression).
provider "standesamt" {
  alias = "custom"
  schema_reference = {
    custom_url = "../../schemas"
  }
  environment = "prod"
  separator   = "-"
  convention  = "default"
}
