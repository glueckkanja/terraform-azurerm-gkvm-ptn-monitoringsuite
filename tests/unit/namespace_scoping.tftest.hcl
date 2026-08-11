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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ContainerService/managedClusters/aks-test"]
  alert_profile       = "kubernetes_workload"
  apply_default_rules = true
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  name_prefixes       = ["CUST-PROD"]
  tags                = { environment = "test" }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
      severities      = [0, 1, 2, 3, 4]
    }
  ]

  defaults_override = {
    kubernetes_workload = "{\"metric_alerts\":{},\"log_alerts\":{\"pod_crashloop\":{\"name\":\"pod-crashloop\",\"description\":\"Crashloop detected\",\"severity\":1,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"KubePodInventory | where ClusterId =~ \\\"$${primary_scope}\\\" | where $${namespace_filter}\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0},\"time_aggregation_method\":\"Count\"}}}"
  }
}

run "namespace_unset_keeps_cluster_wide_behavior" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = can(regex("where true", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].criteria[0].query))
    error_message = "When namespace is unset, namespace_filter must render to true (cluster-wide behavior)."
  }

  assert {
    condition     = !can(regex("team-a", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].name))
    error_message = "Alert name must not contain a namespace suffix when namespace is unset."
  }

  assert {
    condition     = can(regex("^\\[CUST\\] ", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].description))
    error_message = "Description prefix should retain customer prefix when namespace is unset."
  }
}

run "namespace_set_adds_query_filter_name_suffix_and_description_prefix" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    namespace            = "team-a"
  }

  assert {
    condition     = can(regex("Namespace =~ \\\"team-a\\\"", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].criteria[0].query))
    error_message = "When namespace is set, query must include Namespace =~ \"team-a\"."
  }

  assert {
    condition     = can(regex("\\[ns/team-a\\]", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].description))
    error_message = "Description prefix should include [ns/team-a] when namespace is set."
  }
}

run "invalid_namespace_fails_validation" {
  command = plan

  expect_failures = [var.namespace]

  variables {
    naming_configuration = run.setup.naming_configuration
    namespace            = "Team_A"
  }
}

run "namespace_for_non_kubernetes_profile_fails_validation" {
  command = plan

  expect_failures = [var.namespace]

  variables {
    naming_configuration = run.setup.naming_configuration
    alert_profile        = "firewall"
    namespace            = "team-a"
  }
}