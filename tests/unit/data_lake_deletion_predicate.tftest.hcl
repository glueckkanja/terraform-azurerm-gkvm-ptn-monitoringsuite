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
# Shared variables for the data_lake profile.
#
# defaults_override carries the two new log alert definitions with their
# query_template containing the ${data_lake_deletion_exclusion_predicate}
# token.  The $${...} HCL escaping produces the literal ${...} string that
# locals.defaults.tf's replace() chain expects.
# ---------------------------------------------------------------------------

variables {
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sadatalaketest"]
  alert_profile       = "data_lake"
  apply_default_rules = true
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
      severities      = [0, 1, 2, 3, 4]
    }
  ]

  # Minimal data_lake profile: no metric alerts, just the two deletion log alerts.
  # query_template tokens use $${...} (HCL escape) so the string passed to
  # jsondecode() contains the literal ${...} that the replace() chain replaces.
  defaults_override = {
    data_lake = "{\"metric_alerts\":{},\"log_alerts\":{\"default_container_deletion\":{\"name\":\"container-deletion\",\"description\":\"ADLS Gen2 - Container deletion\",\"severity\":1,\"time_window\":\"PT5M\",\"frequency\":\"PT1M\",\"query_template\":\"StorageBlobLogs | where not($${data_lake_deletion_exclusion_predicate})\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":0}},\"default_directory_deletion\":{\"name\":\"directory-deletion\",\"description\":\"ADLS Gen2 - Directory deletion\",\"severity\":2,\"time_window\":\"PT5M\",\"frequency\":\"PT1M\",\"query_template\":\"StorageBlobLogs | where not($${data_lake_deletion_exclusion_predicate})\",\"time_aggregation_method\":\"Count\",\"trigger\":{\"operator\":\"GreaterThan\",\"threshold\":50}}}}"
  }
}

# ---------------------------------------------------------------------------
# Case 1: empty data_lake_deletion_exclusions (the default) must produce the
# predicate literal "false", so that not(false) is a true no-op and existing
# customers see zero behaviour change.
# ---------------------------------------------------------------------------

run "empty_exclusions_produces_false_predicate_no_op" {
  command = plan

  variables {
    naming_configuration          = run.setup.naming_configuration
    data_lake_deletion_exclusions = []
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 2
    error_message = "Data lake profile must create exactly two log alerts: default_container_deletion and default_directory_deletion."
  }

  assert {
    condition     = can(regex("not\\(false\\)", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "container-deletion: empty data_lake_deletion_exclusions must render the predicate as 'false', producing 'where not(false)' — a true no-op that keeps every row."
  }

  assert {
    condition     = can(regex("not\\(false\\)", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_directory_deletion"].criteria[0].query))
    error_message = "directory-deletion: empty data_lake_deletion_exclusions must also produce 'where not(false)' — behaviour must be identical across both deletion alerts."
  }
}

# ---------------------------------------------------------------------------
# Case 2: single exclusion rule with both paths and object_ids set must
# produce one correctly structured sub-predicate with an identity check.
# The same predicate must land in both the container-deletion and the
# directory-deletion alert.
# ---------------------------------------------------------------------------

run "single_rule_with_object_ids_produces_full_sub_predicate" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths      = ["raw/sensitive"]
        object_ids = ["11111111-1111-1111-1111-111111111111"]
      }
    ]
  }

  assert {
    condition     = can(regex("has_any", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Single-rule predicate must use 'has_any' for path matching (ObjectKey has_any)."
  }

  assert {
    condition     = can(regex("raw/sensitive", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Single-rule predicate must embed the specified path."
  }

  assert {
    condition     = can(regex("11111111-1111-1111-1111-111111111111", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Single-rule predicate must embed the specified object_id for the identity check."
  }

  assert {
    condition     = can(regex("RequesterObjectId in", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Single-rule predicate with a non-empty object_ids must include a RequesterObjectId identity check."
  }

  # Verify the same resolved predicate reaches the directory-deletion alert —
  # both alerts share the same substitution path and must produce identical KQL.
  assert {
    condition     = can(regex("11111111-1111-1111-1111-111111111111", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_directory_deletion"].criteria[0].query))
    error_message = "directory-deletion alert must receive the same exclusion predicate as container-deletion — the substitution is shared."
  }

  assert {
    condition     = can(regex("raw/sensitive", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_directory_deletion"].criteria[0].query))
    error_message = "directory-deletion alert must embed the specified path, same as container-deletion."
  }
}

# ---------------------------------------------------------------------------
# Case 3: multiple exclusion rules must be joined with ' or '.
# No cross-contamination: rule 2's empty object_ids must not inherit
# rule 1's object_id.  The exact count of dynamic([]) occurrences (2 — one
# for array_length, one for in()) enforces this mechanically.
# ---------------------------------------------------------------------------

run "multi_rule_ors_predicates_without_cross_contamination" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths      = ["path/a"]
        object_ids = ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]
      },
      {
        paths      = ["path/b"]
        object_ids = []
      }
    ]
  }

  assert {
    condition     = can(regex(" or ", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Two exclusion rules must be joined with ' or ' in the predicate."
  }

  assert {
    condition     = can(regex("path/a", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Rule 1 path 'path/a' must appear in the predicate."
  }

  assert {
    condition     = can(regex("path/b", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Rule 2 path 'path/b' must appear in the predicate."
  }

  assert {
    condition     = can(regex("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Rule 1 object_id must appear in its sub-predicate."
  }

  # Cross-contamination guard: rule 2 has empty object_ids, so it must produce
  # dynamic([]) twice (once for array_length, once for in()).  If rule 1's
  # object_id leaked into rule 2 the count would change.
  assert {
    condition     = length(regexall("dynamic\\(\\[\\]\\)", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query)) == 2
    error_message = "Rule 2 (empty object_ids) must produce exactly 2 dynamic([]) tokens — more would mean rule 1's object_ids bled into rule 2."
  }

  # Verify the same OR-joined predicate reaches the directory-deletion alert.
  assert {
    condition     = can(regex(" or ", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_directory_deletion"].criteria[0].query))
    error_message = "directory-deletion alert must also receive the OR-joined multi-rule predicate."
  }
}

# ---------------------------------------------------------------------------
# Case 4: rule with empty object_ids (the optional default) must degenerate
# to a path-only match via the array_length(dynamic([])) == 0 short-circuit,
# NOT produce the empty-list 'false' predicate.
# ---------------------------------------------------------------------------

run "empty_object_ids_degenerates_to_path_only_via_short_circuit" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths = ["data/backups"]
        # object_ids omitted — defaults to []
      }
    ]
  }

  assert {
    condition     = can(regex("data/backups", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Path 'data/backups' must appear in the predicate."
  }

  # The short-circuit: array_length(dynamic([])) == 0 is always true, making
  # the RequesterObjectId check irrelevant and producing a path-only suppression.
  assert {
    condition     = can(regex("array_length\\(dynamic\\(\\[\\]\\)\\) == 0", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "Empty object_ids must produce 'array_length(dynamic([])) == 0' to short-circuit the identity check — this is the path-only degenerate form."
  }

  # Must not be the empty-list no-op — a non-empty exclusion list must
  # actually suppress matching rows.
  assert {
    condition     = !can(regex("not\\(false\\)", azurerm_monitor_scheduled_query_rules_alert_v2.this["default_container_deletion"].criteria[0].query))
    error_message = "A non-empty exclusion list must not produce the empty-list 'false' predicate — that would suppress nothing."
  }
}

# ---------------------------------------------------------------------------
# Case 5: variable validation must reject an entry where paths is empty.
# An object_ids-only rule suppresses nothing (no path scope) and is
# therefore always a misconfiguration.
# ---------------------------------------------------------------------------

run "validation_rejects_entry_with_empty_paths" {
  command = plan

  expect_failures = [var.data_lake_deletion_exclusions]

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths      = []
        object_ids = ["22222222-2222-2222-2222-222222222222"]
      }
    ]
  }
}

# ---------------------------------------------------------------------------
# Case 6: variable validation must reject an entry where paths contains an
# empty string.  An empty-string path in KQL has_any can match all rows,
# silently suppressing every deletion alert — a dangerous misconfiguration.
# ---------------------------------------------------------------------------

run "validation_rejects_entry_with_empty_string_path" {
  command = plan

  expect_failures = [var.data_lake_deletion_exclusions]

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths      = [""]
        object_ids = []
      }
    ]
  }
}

# ---------------------------------------------------------------------------
# Case 7: validation must also reject whitespace-only path entries.
# ---------------------------------------------------------------------------

run "validation_rejects_entry_with_whitespace_only_path" {
  command = plan

  expect_failures = [var.data_lake_deletion_exclusions]

  variables {
    naming_configuration = run.setup.naming_configuration
    data_lake_deletion_exclusions = [
      {
        paths = ["  "]
      }
    ]
  }
}
