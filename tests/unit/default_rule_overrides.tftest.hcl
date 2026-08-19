# Regression coverage for default_alert_rules_configuration overrides.
#
# The variable was typed `any`, so an override map with mixed value shapes gets
# unified by OpenTofu to map(map(string)) — every field arrives stringified.
# `disable_rule = true` then became "true", and `"true" != true` is always true,
# so the rule was never filtered out. The typed object schema converts per
# attribute instead, which is what these runs pin down.

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
  alert_profile       = "testprofile"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  # testprofile: rule_keep + rule_drop (identical shape), rule_bw (bandwidth multiplier)
  # appzone: two rules, used to prove the opt-in path still works
  defaults_override = {
    testprofile = "{\"metric_alerts\":{\"rule_keep\":{\"name\":\"keep-alert\",\"description\":\"Keep\",\"severity\":3,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"alert_criterias\":[{\"metric_name\":\"FirewallHealth\",\"operator\":\"LessThan\",\"aggregation\":\"Average\",\"threshold\":95}]},\"rule_drop\":{\"name\":\"drop-alert\",\"description\":\"Drop\",\"severity\":3,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"alert_criterias\":[{\"metric_name\":\"Throughput\",\"operator\":\"GreaterThan\",\"aggregation\":\"Average\",\"threshold\":10}]},\"rule_bw\":{\"name\":\"bandwidth-alert\",\"description\":\"Bandwidth\",\"severity\":2,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"bandwidth_multiplier\":true,\"alert_criterias\":[{\"metric_name\":\"Throughput\",\"operator\":\"GreaterThan\",\"aggregation\":\"Average\",\"threshold\":0.8}]}},\"log_alerts\":{\"log_keep\":{\"name\":\"log-keep\",\"description\":\"Log keep\",\"severity\":3,\"time_window\":\"PT15M\",\"frequency\":\"PT5M\",\"query_template\":\"AzureDiagnostics | count\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":5}}}}"
    appzone     = "{\"metric_alerts\":{\"app_one\":{\"name\":\"app-one\",\"description\":\"App one\",\"severity\":3,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"alert_criterias\":[{\"metric_name\":\"FirewallHealth\",\"operator\":\"LessThan\",\"aggregation\":\"Average\",\"threshold\":95}]},\"app_two\":{\"name\":\"app-two\",\"description\":\"App two\",\"severity\":3,\"window_size\":\"PT5M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/azureFirewalls\",\"alert_criterias\":[{\"metric_name\":\"Throughput\",\"operator\":\"GreaterThan\",\"aggregation\":\"Average\",\"threshold\":10}]}},\"log_alerts\":{}}"
  }
}

# Baseline — without overrides every default rule is created (opt-out profile)
run "all_defaults_created_without_overrides" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 3
    error_message = "All three testprofile metric alerts should be created when nothing is overridden."
  }
}

# disable_rule as a native bool
run "native_bool_disable_rule_removes_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_drop = { disable_rule = true }
    }
  }

  assert {
    condition     = !contains(keys(azurerm_monitor_metric_alert.this), "rule_drop")
    error_message = "disable_rule = true must remove rule_drop."
  }

  assert {
    condition     = contains(keys(azurerm_monitor_metric_alert.this), "rule_keep")
    error_message = "Disabling one rule must not affect the others."
  }
}

# disable_rule as the stringified "true" that map(map(string)) unification produces
run "stringified_disable_rule_removes_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_drop = { disable_rule = "true" }
    }
  }

  assert {
    condition     = !contains(keys(azurerm_monitor_metric_alert.this), "rule_drop")
    error_message = "disable_rule = \"true\" (stringified by type unification) must remove rule_drop."
  }
}

# The original bug report: mixed value shapes in one map force unification to strings
run "mixed_shape_overrides_still_disable" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_keep = { name = "renamed-keep" }
      rule_drop = { disable_rule = true }
    }
  }

  assert {
    condition     = !contains(keys(azurerm_monitor_metric_alert.this), "rule_drop")
    error_message = "A mixed-shape override map must still honour disable_rule on rule_drop."
  }

  assert {
    condition     = contains(keys(azurerm_monitor_metric_alert.this), "rule_keep")
    error_message = "rule_keep carries only a name override and must survive."
  }
}

# disable_rule must also drop log alerts, not just metric alerts
run "disable_rule_removes_log_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      log_keep = { disable_rule = true }
      rule_bw  = { threshold = 0.5 }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 0
    error_message = "disable_rule = true must remove the default log alert."
  }
}

# severity and threshold arriving as strings must behave as numbers
run "stringified_severity_and_threshold" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_keep = { severity = "1", threshold = "80" }
    }
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["rule_keep"].severity == 1
    error_message = "severity override must reach the resource as the number 1."
  }

  assert {
    condition     = one(azurerm_monitor_metric_alert.this["rule_keep"].criteria).threshold == 80
    error_message = "threshold override must reach the criteria as the number 80."
  }
}

# bandwidth_multiplier rules multiply the override by var.bandwidth
run "threshold_override_multiplies_by_bandwidth" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    bandwidth            = 1000

    default_alert_rules_configuration = {
      rule_bw = { threshold = 0.5 }
    }
  }

  assert {
    condition     = one(azurerm_monitor_metric_alert.this["rule_bw"].criteria).threshold == 500
    error_message = "bandwidth_multiplier rules must multiply the overridden threshold by var.bandwidth."
  }
}

# Unset optional attributes must fall back to the catalog value, not null
run "partial_override_keeps_catalog_defaults" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      rule_keep = { severity = 0 }
    }
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["rule_keep"].window_size == "PT5M"
    error_message = "window_size was not overridden and must keep the catalog value."
  }

  assert {
    condition     = one(azurerm_monitor_metric_alert.this["rule_keep"].criteria).threshold == 95
    error_message = "threshold was not overridden and must keep the catalog value."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["rule_keep"].severity == 0
    error_message = "severity = 0 must be applied, not treated as absent."
  }
}

# appzone stays opt-in: only listed keys are created
run "appzone_opt_in_unaffected" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    alert_profile        = "appzone"

    default_alert_rules_configuration = {
      app_one = {}
    }
  }

  assert {
    condition     = keys(azurerm_monitor_metric_alert.this) == ["app_one"]
    error_message = "appzone must create only the rules listed in default_alert_rules_configuration."
  }
}
