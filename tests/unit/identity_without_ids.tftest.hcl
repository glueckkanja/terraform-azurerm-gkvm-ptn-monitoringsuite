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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"]
  alert_profile       = "identity_profile"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  defaults_override = {
    identity_profile = "{\"metric_alerts\":{},\"log_alerts\":{\"needs_msi\":{\"name\":\"needs-msi\",\"description\":\"Query with managed identity\",\"severity\":2,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"arg('').resources | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0},\"identity\":{\"enable\":true,\"type\":\"SystemAssigned\"}}}}"
  }
}

# A profile identity block without identity_ids (the appzone update-management
# shape) must not fail the plan — length() on an explicit null did.
run "identity_without_identity_ids" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = tolist(azurerm_monitor_scheduled_query_rules_alert_v2.this["needs_msi"].identity)[0].type == "SystemAssigned"
    error_message = "The identity block must be created with the profile's type."
  }
}
