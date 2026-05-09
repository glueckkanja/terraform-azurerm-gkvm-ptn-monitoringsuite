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

  # Two globally defined action groups: MSP (all severities) and customer (sev 2-4 only)
  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-msp"
      severities      = [0, 1, 2, 3, 4]
    },
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"
      severities      = [2, 3, 4]
    }
  ]
}

# Custom metric alert with action_group_ids routes only to those groups, ignoring severity routing
run "custom_metric_alert_routes_only_to_specified_groups" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_metric_alerts = {
      customer_only = {
        name             = "Customer Only Alert"
        severity         = 0 # sev 0 — only ag-msp covers this under normal routing
        metric_namespace = "Microsoft.Network/azureFirewalls"
        alert_criterias = [{
          metric_name = "FirewallHealth"
          operator    = "LessThan"
          aggregation = "Average"
          threshold   = 80
        }]
        # Explicit override: route to customer group only, despite sev 0
        action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) > 0
    error_message = "Expected at least one metric alert to be created."
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["customer_only"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"
    ]) == 1
    error_message = "Customer action group should be present when action_group_ids is set."
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["customer_only"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-msp"
    ]) == 0
    error_message = "MSP action group must NOT appear when action_group_ids override is explicitly set."
  }
}

# Default alert with action_group_ids override via default_alert_rules_configuration
run "default_metric_alert_routes_only_to_specified_groups" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      fw_health = {
        action_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) > 0
    error_message = "Default firewall profile should create metric alerts."
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["fw_health"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-msp"
    ]) == 0
    error_message = "MSP action group must NOT appear on fw_health when action_group_ids override is set."
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["fw_health"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"
    ]) == 1
    error_message = "Customer action group should be the only action group on fw_health."
  }
}

# action_group_ids = [] (empty list) intentionally silences the alert — no severity routing fallback
run "empty_action_group_ids_notifies_nobody" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_metric_alerts = {
      silent_alert = {
        name             = "Silent Alert"
        severity         = 0
        metric_namespace = "Microsoft.Network/azureFirewalls"
        alert_criterias = [{
          metric_name = "FirewallHealth"
          operator    = "LessThan"
          aggregation = "Average"
          threshold   = 80
        }]
        action_group_ids = []
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this["silent_alert"].action) == 0
    error_message = "An empty action_group_ids list must produce zero action blocks — severity routing must not fall back."
  }
}

# Without action_group_ids, severity routing continues to apply unchanged
run "without_action_group_ids_severity_routing_is_unchanged" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_metric_alerts = {
      standard_alert = {
        name             = "Standard Alert"
        severity         = 0 # only ag-msp covers sev 0
        metric_namespace = "Microsoft.Network/azureFirewalls"
        alert_criterias = [{
          metric_name = "FirewallHealth"
          operator    = "LessThan"
          aggregation = "Average"
          threshold   = 80
        }]
        # no action_group_ids — severity routing applies
      }
    }
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["standard_alert"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-msp"
    ]) == 1
    error_message = "Without action_group_ids, MSP group (sev 0-4) should receive sev 0 alerts."
  }

  assert {
    condition = length([
      for ag in azurerm_monitor_metric_alert.this["standard_alert"].action :
      ag.action_group_id if ag.action_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-customer"
    ]) == 0
    error_message = "Customer group (sev 2-4 only) should NOT receive sev 0 alerts under normal routing."
  }
}
