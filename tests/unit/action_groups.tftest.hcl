mock_provider "azurerm" {}
mock_provider "standesamt" {}
mock_provider "modtm" {}
mock_provider "random" {}

run "setup" {
  module {
    source = "./tests/unit/setup"
  }

  providers = {
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}

variables {
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"]
  alert_profile       = null
  apply_default_rules = false
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = {}

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-external"
      severities      = [0, 1]
    }
  ]

  action_groups = {
    internal = {
      short_name = "internal"
      severities = [2, 3, 4]
      email_receivers = {
        ops = {
          name                    = "ops-team"
          email_address           = "ops@test.com"
          use_common_alert_schema = true
        }
      }
    }
    customer = {
      short_name = "customer"
      severities = [2, 3, 4]
      naming = {
        name       = "customer-ops"
        convention = "default"
        prefixes   = ["pfx"]
        suffixes   = ["sfx"]
      }
      email_receivers = {
        ops = {
          name          = "ops-team"
          email_address = "ops@test.com"
        }
      }
    }
  }
}

run "creates_module_action_group" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 2
    error_message = "Should create one module action group per action_groups entry."
  }
}

run "names_action_group_from_key_with_module_naming" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  # module-level convention is passthrough: the key is the resource name
  assert {
    condition     = azurerm_monitor_action_group.this["internal"].name == "internal"
    error_message = "Without naming overrides the map key under the module-level convention is the name, got ${azurerm_monitor_action_group.this["internal"].name}."
  }
}

run "honors_per_group_naming_overrides" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = azurerm_monitor_action_group.this["customer"].name != "customer" && azurerm_monitor_action_group.this["customer"].name != "customer-ops"
    error_message = "naming.convention must override the module-level passthrough convention, got ${azurerm_monitor_action_group.this["customer"].name}."
  }

  assert {
    condition     = strcontains(azurerm_monitor_action_group.this["customer"].name, "customer-ops")
    error_message = "naming.name must replace the map key as the base name, got ${azurerm_monitor_action_group.this["customer"].name}."
  }

  assert {
    condition     = strcontains(azurerm_monitor_action_group.this["customer"].name, "pfx") && strcontains(azurerm_monitor_action_group.this["customer"].name, "sfx")
    error_message = "naming.prefixes and naming.suffixes must be applied, got ${azurerm_monitor_action_group.this["customer"].name}."
  }
}
