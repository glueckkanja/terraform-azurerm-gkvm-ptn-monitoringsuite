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

# ---------------------------------------------------------------------------
# Shared variables for the kubernetes_workload profile.
#
# defaults_override carries one representative log alert whose query_template
# contains the ${namespace_filter} token, same $${...} HCL escaping used by
# the other locals.defaults.tf substitution tests.
# ---------------------------------------------------------------------------

variables {
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ContainerService/managedClusters/aks-test"]
  alert_profile       = "kubernetes_workload"
  apply_default_rules = true
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  defaults_override = {
    kubernetes_workload = "{\"metric_alerts\":{},\"log_alerts\":{\"pod_crashloop\":{\"name\":\"pod-crashloop\",\"description\":\"A pod in the cluster is in CrashLoopBackOff\",\"severity\":1,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"KubePodInventory | where ClusterId =~ \\\"$${primary_scope}\\\" | where $${namespace_filter} | where ContainerStatusReason == \\\"CrashLoopBackOff\\\"\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}}}}"
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

# ---------------------------------------------------------------------------
# Case 1: namespace unset (default) must render the filter as "true" —
# a true no-op that keeps cluster-wide behaviour unchanged — and must not
# add a namespace suffix to the alert name or description.
# ---------------------------------------------------------------------------

run "unset_namespace_is_cluster_wide_no_op" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = can(regex("where true", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].criteria[0].query))
    error_message = "Unset namespace must render namespace_filter as the literal 'true', keeping the query cluster-wide."
  }

  assert {
    condition     = !can(regex("Namespace =~", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].criteria[0].query))
    error_message = "Unset namespace must not emit a Namespace =~ predicate."
  }

  assert {
    condition     = !can(regex("\\[ns/", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].description))
    error_message = "Unset namespace must not add a [ns/...] description segment."
  }
}

# ---------------------------------------------------------------------------
# Case 2: namespace set must scope the query to that namespace and
# identify it in the alert name and description.
# ---------------------------------------------------------------------------

run "set_namespace_scopes_query_name_and_description" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    namespace            = "team-a"
  }

  assert {
    condition     = can(regex("Namespace =~ \"team-a\"", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].criteria[0].query))
    error_message = "Set namespace must render namespace_filter as 'Namespace =~ \"team-a\"'."
  }

  # Note: alert naming (suffix folding) goes through provider::standesamt::name,
  # which mock_provider "standesamt" collapses to a passthrough of config.name —
  # no existing test in this suite asserts on .name for the same reason.
  # The suffix logic itself lives in locals.tf log_alert_names_v2/v1 and is only
  # verifiable against the real provider (see examples/default).

  assert {
    condition     = can(regex("^\\[ns/team-a\\] ", azurerm_monitor_scheduled_query_rules_alert_v2.this["pod_crashloop"].description))
    error_message = "Set namespace must prefix the description with [ns/team-a] for PagerDuty identification."
  }
}

# ---------------------------------------------------------------------------
# Case 3: namespace validation must reject a non-RFC-1123 value.
# ---------------------------------------------------------------------------

run "validation_rejects_invalid_namespace_format" {
  command = plan

  expect_failures = [var.namespace]

  variables {
    naming_configuration = run.setup.naming_configuration
    namespace            = "Team_A"
  }
}

# ---------------------------------------------------------------------------
# Case 4: namespace validation must reject use outside kubernetes_workload —
# the whole point of the scoping is that it only makes sense in a container
# context.
# ---------------------------------------------------------------------------

run "validation_rejects_namespace_on_non_container_profile" {
  command = plan

  expect_failures = [var.namespace]

  variables {
    naming_configuration = run.setup.naming_configuration
    namespace            = "team-a"
    alert_profile        = "firewall"

    defaults_override = {
      firewall = "{\"metric_alerts\":{},\"log_alerts\":{}}"
    }
  }
}
