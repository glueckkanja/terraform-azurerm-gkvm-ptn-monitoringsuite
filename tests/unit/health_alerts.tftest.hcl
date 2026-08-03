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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  alert_profile       = null
  apply_default_rules = false
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-health"
      severities      = [0, 1, 2, 3, 4]
    }
  ]
}

run "health_alerts_disabled_by_default_creates_nothing" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health) == 0
    error_message = "Service health alerts must not be created when not enabled."
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 0
    error_message = "Resource health alerts must not be created when not enabled."
  }
}

run "service_health_enabled_creates_one_per_subscription" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    health_alerts = {
      service_health = {
        enabled = true
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health) == 1
    error_message = "Exactly one service health alert expected per unique subscription."
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 0
    error_message = "Resource health alert must stay disabled when only service_health is enabled."
  }
}

run "resource_health_enabled_creates_alert_with_filters" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    health_alerts = {
      resource_health = {
        enabled = true
        current = ["Degraded", "Unavailable"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 1
    error_message = "Exactly one resource health alert expected per unique subscription."
  }
}

run "duplicate_subscriptions_deduplicate_to_one_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-a",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-b",
    ]

    health_alerts = {
      service_health  = { enabled = true }
      resource_health = { enabled = true }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health) == 1
    error_message = "Two scopes in the same subscription must collapse to one service health alert."
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 1
    error_message = "Two scopes in the same subscription must collapse to one resource health alert."
  }
}

run "statuses_filter_is_applied" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    health_alerts = {
      resource_health = {
        enabled  = true
        statuses = ["Active"]
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health) == 1
    error_message = "Resource health alert with statuses filter should plan successfully."
  }

  assert {
    condition     = contains(tolist(azurerm_monitor_activity_log_alert.resource_health["/subscriptions/00000000-0000-0000-0000-000000000000"].criteria[0].statuses), "Active")
    error_message = "statuses filter must be propagated to criteria.statuses."
  }
}

run "only_sev4_action_groups_are_attached" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    action_group_routing = [
      {
        action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-pagerduty-sev0"
        severities      = [0]
      },
      {
        action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-tickets"
        severities      = [1, 2, 3, 4]
      },
    ]

    health_alerts = {
      service_health  = { enabled = true }
      resource_health = { enabled = true }
    }
  }

  assert {
    condition = toset([for a in azurerm_monitor_activity_log_alert.service_health["/subscriptions/00000000-0000-0000-0000-000000000000"].action : a.action_group_id]) == toset([
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-tickets"
    ])
    error_message = "Service health alerts must attach exactly the action groups whose severities include 4 (health alerts are fixed Sev4)."
  }

  assert {
    condition = toset([for a in azurerm_monitor_activity_log_alert.resource_health["/subscriptions/00000000-0000-0000-0000-000000000000"].action : a.action_group_id]) == toset([
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-tickets"
    ])
    error_message = "Resource health alerts must attach exactly the action groups whose severities include 4 (health alerts are fixed Sev4)."
  }
}

run "no_sev4_action_group_leaves_health_alerts_without_actions" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    action_group_routing = [
      {
        action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-pagerduty-sev0"
        severities      = [0]
      },
    ]

    health_alerts = {
      service_health = { enabled = true }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health["/subscriptions/00000000-0000-0000-0000-000000000000"].action) == 0
    error_message = "A Sev0-only action group must not be attached to health alerts."
  }
}

run "distinct_subscriptions_create_separate_alerts" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-a",
      "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-b",
    ]

    health_alerts = {
      service_health = { enabled = true }
    }
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.service_health) == 2
    error_message = "Two scopes in different subscriptions must produce two service health alerts."
  }
}
