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

run "no_prefix_when_name_prefixes_empty" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = []
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) > 0
    error_message = "Metric alert should be created."
  }

  assert {
    condition     = !can(regex("^\\[", azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description))
    error_message = "Metric alert description should not start with [ when name_prefixes is empty."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description == "Firewall health"
    error_message = "Metric alert description should be the original description without prefix."
  }
}

run "single_prefix_applied_to_metric_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["CUST"]
  }

  assert {
    condition     = can(regex("^\\[CUST\\] ", azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description))
    error_message = "Metric alert description should start with [CUST] prefix."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description == "[CUST] Firewall health"
    error_message = "Metric alert description should contain the prefixed text."
  }
}

run "multiple_prefixes_uses_first_only" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["CUST", "ENV"]
  }

  assert {
    condition     = can(regex("^\\[CUST\\] ", azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description))
    error_message = "Metric alert description should use only the first name_prefix."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description == "[CUST] Firewall health"
    error_message = "Metric alert description should contain only the first prefix."
  }
}

run "service_health_alert_with_prefix" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["CUST"]

    scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000"]

    health_alerts = {
      service_health = {
        enabled = true
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health) == 1
    error_message = "Service health alert should be created."
  }

  assert {
    condition     = can(regex("^\\[CUST\\] Service Health alert", azurerm_monitor_activity_log_alert.service_health["/subscriptions/00000000-0000-0000-0000-000000000000"].description))
    error_message = "Service health alert description should start with prefix."
  }
}

run "resource_health_alert_with_prefix" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["APP"]

    scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000"]

    health_alerts = {
      resource_health = {
        enabled = true
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 1
    error_message = "Resource health alert should be created."
  }

  assert {
    condition     = can(regex("^\\[APP\\] Resource Health alert", azurerm_monitor_activity_log_alert.resource_health["/subscriptions/00000000-0000-0000-0000-000000000000"].description))
    error_message = "Resource health alert description should start with prefix."
  }
}

run "custom_log_alert_with_prefix" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["CUST", "APP"]

    apply_default_rules = false

    custom_log_alerts = {
      test_query = {
        name        = "Test Alert"
        description = "Test query alert"
        severity    = 2
        enabled     = true
        query       = "KubeEvents | where TimeGenerated > ago(5m)"
        trigger = {
          operator  = "GreaterThan"
          threshold = 5
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 1
    error_message = "Custom log alert should be created."
  }

  assert {
    condition     = can(regex("^\\[CUST\\] Test query alert", azurerm_monitor_scheduled_query_rules_alert_v2.this[keys(azurerm_monitor_scheduled_query_rules_alert_v2.this)[0]].description))
    error_message = "Custom log alert description should use only the first name_prefix."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this[keys(azurerm_monitor_scheduled_query_rules_alert_v2.this)[0]].description == "[CUST] Test query alert"
    error_message = "Custom log alert description should contain only the first prefix."
  }
}

run "compound_monitoring_key_uses_customer_part_only" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["GABCF-ADF"]
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this[keys(azurerm_monitor_metric_alert.this)[0]].description == "[GABCF] Firewall health"
    error_message = "Compound monitoring key GABCF-ADF should produce prefix [GABCF], not [GABCF-ADF]."
  }
}

run "empty_description_with_prefix" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    name_prefixes        = ["PROD"]

    apply_default_rules = false

    custom_log_alerts = {
      no_desc = {
        name        = "No Description"
        description = ""
        severity    = 2
        enabled     = true
        query       = "KubeEvents | where TimeGenerated > ago(5m)"
        trigger = {
          operator  = "GreaterThan"
          threshold = 5
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 1
    error_message = "Log alert with empty description should be created."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this[keys(azurerm_monitor_scheduled_query_rules_alert_v2.this)[0]].description == "[PROD]"
    error_message = "Log alert with empty description should contain only the prefix."
  }
}
