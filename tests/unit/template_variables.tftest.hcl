# Consumer-defined template variables: every key of var.template_variables becomes a
# ${key} placeholder in log alert query templates, substituted after the built-in ones.

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
  alert_profile       = "testprofile"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  # log_plain carries no placeholder, log_param carries a consumer placeholder next to a built-in one.
  defaults_override = {
    testprofile = "{\"metric_alerts\":{},\"log_alerts\":{\"log_plain\":{\"name\":\"log-plain\",\"description\":\"Plain\",\"severity\":3,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"AzureDiagnostics | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":5}},\"log_param\":{\"name\":\"log-param\",\"description\":\"Param\",\"severity\":2,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"PowerBIDatasetsWorkspace | where _ResourceId startswith \\\"$${primary_scope}\\\" | where $${critical_predicate} | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}}}}"
  }
}

run "placeholder_substituted_from_template_variables" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    template_variables = {
      critical_predicate = "(PowerBIWorkspaceName == \"Finance [PRD]\" and ArtifactName == \"Sales\")"
    }
  }

  assert {
    condition     = strcontains(azurerm_monitor_scheduled_query_rules_alert_v2.this["log_param"].criteria[0].query, "where (PowerBIWorkspaceName == \"Finance [PRD]\" and ArtifactName == \"Sales\")")
    error_message = "The consumer placeholder must be replaced by the template variable value."
  }

  assert {
    condition     = strcontains(azurerm_monitor_scheduled_query_rules_alert_v2.this["log_param"].criteria[0].query, "startswith \"/subscriptions/00000000-0000-0000-0000-000000000000")
    error_message = "Built-in placeholders must still be substituted when template variables are set."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["log_plain"].criteria[0].query == "AzureDiagnostics | count"
    error_message = "Queries without placeholders must be untouched."
  }
}

run "queries_unchanged_without_template_variables" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = strcontains(azurerm_monitor_scheduled_query_rules_alert_v2.this["log_param"].criteria[0].query, "$${critical_predicate}")
    error_message = "Without template variables the consumer placeholder must stay literal (byte-identical behaviour for existing consumers)."
  }
}
