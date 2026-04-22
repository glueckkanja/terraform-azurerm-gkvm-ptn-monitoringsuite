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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"]
  alert_profile       = "firewall"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  defaults_override = {
    firewall = "{\"metric_alerts\":{\"fw_health\":{\"name\":\"azfw-health\",\"description\":\"Firewall health\",\"severity\":0,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"alert_criterias\":[{\"metric_name\":\"FirewallHealth\",\"operator\":\"LessThan\",\"aggregation\":\"Average\",\"threshold\":95}]}},\"log_alerts\":{}}"
  }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
      severities      = [0, 1, 2, 3, 4]
    }
  ]
}

run "validates_module_loads" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(var.scopes) > 0
    error_message = "Scopes must not be empty."
  }
}

run "firewall_profile_creates_metric_alerts" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) > 0
    error_message = "Firewall profile should create at least one metric alert."
  }
}
