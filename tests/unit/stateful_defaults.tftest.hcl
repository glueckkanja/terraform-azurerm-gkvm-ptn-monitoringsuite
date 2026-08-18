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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Fabric/capacities/cap-test"]
  alert_profile       = "stateful_test"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  # rule_stateful:  no auto_mitigation_enabled in the YAML -> module default true
  # rule_muted:     mute_actions_after_alert_duration set -> auto-mitigation forced off
  # rule_failing:   failing_periods from the rule library -> rendered into criteria
  defaults_override = {
    stateful_test = "{\"metric_alerts\":{},\"log_alerts\":{\"rule_stateful\":{\"name\":\"stateful-rule\",\"description\":\"stateful default\",\"severity\":3,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"Heartbeat | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}},\"rule_muted\":{\"name\":\"muted-rule\",\"description\":\"muted default\",\"severity\":2,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"mute_actions_after_alert_duration\":\"P1D\",\"query_template\":\"Heartbeat | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}},\"rule_failing\":{\"name\":\"failing-periods-rule\",\"description\":\"failing periods default\",\"severity\":3,\"time_window\":\"PT5M\",\"frequency\":\"PT5M\",\"auto_mitigation_enabled\":true,\"failing_periods\":{\"number_of_evaluation_periods\":3,\"minimum_failing_periods_to_trigger_alert\":2},\"query_template\":\"Heartbeat | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}}}}"
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

run "default_log_alerts_are_stateful" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_stateful"].auto_mitigation_enabled == true
    error_message = "A default log alert without auto_mitigation_enabled in the rule library must default to stateful (auto_mitigation_enabled = true)."
  }
}

run "muted_rule_keeps_auto_mitigation_off" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_muted"].auto_mitigation_enabled == false
    error_message = "A rule with mute_actions_after_alert_duration must not enable auto-mitigation (azurerm forbids the combination)."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_muted"].mute_actions_after_alert_duration == "P1D"
    error_message = "mute_actions_after_alert_duration from the rule library must be preserved."
  }
}

run "failing_periods_are_rendered" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = one(azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_failing"].criteria[0].failing_periods[*].number_of_evaluation_periods) == 3
    error_message = "failing_periods.number_of_evaluation_periods from the rule library must reach the criteria block."
  }

  assert {
    condition     = one(azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_failing"].criteria[0].failing_periods[*].minimum_failing_periods_to_trigger_alert) == 2
    error_message = "failing_periods.minimum_failing_periods_to_trigger_alert from the rule library must reach the criteria block."
  }
}

run "null_override_fields_fall_back_to_rule_values" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    # A typed consumer object (optional(..., null)) sends explicit nulls for
    # unset fields — they must be ignored, not override the rule values.
    default_alert_rules_configuration = {
      rule_stateful = {
        severity                = null
        frequency               = null
        window_size             = null
        threshold               = null
        auto_mitigation_enabled = null
      }
    }
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_stateful"].severity == 3
    error_message = "An explicit null severity override must fall back to the rule's severity."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_stateful"].evaluation_frequency == "PT5M"
    error_message = "An explicit null frequency override must fall back to the rule's frequency."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_stateful"].auto_mitigation_enabled == true
    error_message = "An explicit null auto_mitigation_enabled override must fall back to the stateful default."
  }
}

run "mute_wins_over_explicit_true_override" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    # azurerm forbids combining mute_actions with auto-mitigation — the guard
    # must win even against an explicit customer override.
    default_alert_rules_configuration = {
      rule_muted = {
        auto_mitigation_enabled = true
      }
    }
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_muted"].auto_mitigation_enabled == false
    error_message = "A rule with mute_actions_after_alert_duration must keep auto-mitigation off even when a customer override requests true."
  }
}

run "explicit_override_disables_auto_mitigation" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_stateful = {
        auto_mitigation_enabled = false
      }
    }
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["rule_stateful"].auto_mitigation_enabled == false
    error_message = "An explicit auto_mitigation_enabled = false override must pass through."
  }
}
