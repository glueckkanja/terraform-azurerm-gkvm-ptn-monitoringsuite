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
  }
}
