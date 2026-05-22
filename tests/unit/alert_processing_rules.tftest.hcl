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
  tags                = {}
}

# ---------------------------------------------------------------------------
# No suppressions by default
# ---------------------------------------------------------------------------

run "default_empty_produces_no_resources" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_suppression.this) == 0
    error_message = "No suppressions should be created when alert_processing_rule_suppressions is empty."
  }
}

# ---------------------------------------------------------------------------
# Databricks managed RG + VM resource type exclusion (user's primary use case)
# ---------------------------------------------------------------------------

run "databricks_rg_and_vm_exclusion" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    alert_processing_rule_suppressions = {
      exclude_databricks_noise = {
        description = "Suppress resource health alerts for Databricks managed RGs and individual VMs"
        condition = {
          target_resource_group = {
            operator = "Contains"
            values   = ["databricks-rg-"]
          }
          target_resource_type = {
            operator = "Equals"
            values   = ["microsoft.compute/virtualmachines"]
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_suppression.this) == 1
    error_message = "Should create exactly one suppression rule."
  }

  assert {
    condition     = azurerm_monitor_alert_processing_rule_suppression.this["exclude_databricks_noise"].enabled == true
    error_message = "Suppression rule should be enabled by default."
  }

  assert {
    condition     = azurerm_monitor_alert_processing_rule_suppression.this["exclude_databricks_noise"].scopes == tolist(["/subscriptions/00000000-0000-0000-0000-000000000000"])
    error_message = "Scopes should inherit from var.scopes when not explicitly set."
  }
}

# ---------------------------------------------------------------------------
# Scope override — entry-level scopes take precedence over var.scopes
# ---------------------------------------------------------------------------

run "scopes_override" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    alert_processing_rule_suppressions = {
      narrow_scope = {
        scopes = ["/subscriptions/11111111-1111-1111-1111-111111111111"]
        condition = {
          severity = {
            operator = "Equals"
            values   = ["Sev4"]
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_suppression.this) == 1
    error_message = "Should create one suppression rule."
  }

  assert {
    condition     = azurerm_monitor_alert_processing_rule_suppression.this["narrow_scope"].scopes == tolist(["/subscriptions/11111111-1111-1111-1111-111111111111"])
    error_message = "Entry-level scopes should override var.scopes."
  }
}

# ---------------------------------------------------------------------------
# Schedule — daily maintenance window suppression
# ---------------------------------------------------------------------------

run "weekly_maintenance_window" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    alert_processing_rule_suppressions = {
      sunday_patching_window = {
        description = "Suppress all alerts during Sunday patching window"
        schedule = {
          time_zone = "W. Europe Standard Time"
          recurrence = {
            weekly = [
              {
                days_of_week = ["Sunday"]
                start_time   = "02:00:00"
                end_time     = "06:00:00"
              }
            ]
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_suppression.this) == 1
    error_message = "Should create one schedule-based suppression rule."
  }
}

# ---------------------------------------------------------------------------
# Multiple rules — condition-only, schedule-only, and combined
# ---------------------------------------------------------------------------

run "multiple_rules" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    alert_processing_rule_suppressions = {
      by_resource_type = {
        condition = {
          target_resource_type = {
            operator = "NotEquals"
            values   = ["microsoft.compute/virtualmachinescalesets"]
          }
        }
      }
      weekend_window = {
        schedule = {
          recurrence = {
            weekly = [
              {
                days_of_week = ["Saturday", "Sunday"]
              }
            ]
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_alert_processing_rule_suppression.this) == 2
    error_message = "Should create two suppression rules."
  }

  assert {
    condition     = output.alert_count.alert_processing_rule_suppressions == 2
    error_message = "alert_count.alert_processing_rule_suppressions should reflect the number of created suppression rules."
  }

  assert {
    condition     = output.alert_count.total >= 2
    error_message = "alert_count.total should include suppression rules."
  }
}

# ---------------------------------------------------------------------------
# Validation guard — empty condition = {} must be rejected
# ---------------------------------------------------------------------------

run "empty_condition_object_rejected" {
  command = plan

  expect_failures = [var.alert_processing_rule_suppressions]

  variables {
    naming_configuration = run.setup.naming_configuration

    alert_processing_rule_suppressions = {
      bad_rule = {
        # condition is set but has no sub-blocks — all-null condition {} would
        # suppress every alert at scope unconditionally, same as no filter.
        condition = {}
      }
    }
  }
}
