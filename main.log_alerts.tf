# ---------------------------------------------------------------------------
# ISO 8601 duration to minutes conversion (for v1 alerts)
# Handles: PT5M, PT1H, PT30M, PT6H, P1D, PT45M, etc.
# ---------------------------------------------------------------------------

locals {
  _duration_to_minutes = { for key, config in local.merged_log_alerts_v1 : key => {
    frequency = (
      can(regex("^PT(\\d+)M$", config.frequency)) ? tonumber(regex("^PT(\\d+)M$", config.frequency)[0]) :
      can(regex("^PT(\\d+)H$", config.frequency)) ? tonumber(regex("^PT(\\d+)H$", config.frequency)[0]) * 60 :
      can(regex("^P(\\d+)D$", config.frequency)) ? tonumber(regex("^P(\\d+)D$", config.frequency)[0]) * 1440 :
      config.frequency
    )
    time_window = (
      can(regex("^PT(\\d+)M$", config.time_window)) ? tonumber(regex("^PT(\\d+)M$", config.time_window)[0]) :
      can(regex("^PT(\\d+)H$", config.time_window)) ? tonumber(regex("^PT(\\d+)H$", config.time_window)[0]) * 60 :
      can(regex("^P(\\d+)D$", config.time_window)) ? tonumber(regex("^P(\\d+)D$", config.time_window)[0]) * 1440 :
      config.time_window
    )
  } }
}

# ---------------------------------------------------------------------------
# v2 — Preferred: alerts WITHOUT metric_trigger
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "this" {
  for_each = local.merged_log_alerts_v2

  name                = local.log_alert_names_v2[each.key]
  resource_group_name = var.resource_group_name
  scopes              = [var.log_analytics_workspace_id]
  description         = try(each.value.description, "")

  location = coalesce(var.log_analytics_workspace_location, var.location)

  evaluation_frequency = each.value.frequency
  window_duration      = each.value.time_window
  severity             = each.value.severity

  mute_actions_after_alert_duration = try(each.value.mute_actions_after_alert_duration, null)
  auto_mitigation_enabled           = try(each.value.auto_mitigation_enabled, true)

  criteria {
    query                   = each.value.query
    operator                = try(each.value.trigger.operator, "GreaterThan")
    threshold               = try(each.value.trigger.threshold, 0)
    time_aggregation_method = try(each.value.time_aggregation_method, "Count")
    metric_measure_column   = try(each.value.metric_measure_column, null)
    resource_id_column      = try(each.value.resource_id_column, null)

    dynamic "dimension" {
      for_each = try(each.value.dimensions, null) != null && try(each.value.dimensions, {}) != {} ? (
        try(tolist(each.value.dimensions), [each.value.dimensions])
      ) : []

      content {
        name     = dimension.value.name
        operator = dimension.value.operator
        values   = dimension.value.values
      }
    }

    dynamic "failing_periods" {
      for_each = try(each.value.failing_periods, null) != null ? [each.value.failing_periods] : []

      content {
        minimum_failing_periods_to_trigger_alert = failing_periods.value.minimum_failing_periods_to_trigger_alert
        number_of_evaluation_periods             = failing_periods.value.number_of_evaluation_periods
      }
    }
  }

  dynamic "identity" {
    for_each = try(each.value.identity.enable, false) || try(each.value.identity.enabled, false) ? [1] : []

    content {
      type         = try(each.value.identity.type, "SystemAssigned")
      identity_ids = length(try(each.value.identity.identity_ids, [])) > 0 ? each.value.identity.identity_ids : null
    }
  }

  action {
    action_groups = [for ag in local.all_action_groups : ag.action_group_id if contains(ag.severities, tonumber(each.value.severity))]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]

    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set when log query alerts are configured."
    }
  }
}

# ---------------------------------------------------------------------------
# v1 — Legacy: alerts WITH metric_trigger (deprecated but still needed)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert" "this" {
  for_each = local.merged_log_alerts_v1

  enabled = true

  name                = local.log_alert_names_v1[each.key]
  resource_group_name = var.resource_group_name
  data_source_id      = var.log_analytics_workspace_id
  description         = try(each.value.description, "")

  location = coalesce(var.log_analytics_workspace_location, var.location)

  frequency   = local._duration_to_minutes[each.key].frequency
  time_window = local._duration_to_minutes[each.key].time_window
  severity    = each.value.severity

  auto_mitigation_enabled = try(each.value.auto_mitigation_enabled, true)

  query = each.value.query

  trigger {
    operator  = try(each.value.trigger.operator, "GreaterThan")
    threshold = try(each.value.trigger.threshold, 0)

    dynamic "metric_trigger" {
      for_each = try(each.value.trigger.metric_trigger, null) != null ? [each.value.trigger.metric_trigger] : (
        try(each.value.trigger.metric_trigger_type, null) != null ? [each.value.trigger] : []
      )

      content {
        operator            = try(metric_trigger.value.operator, "GreaterThan")
        threshold           = try(metric_trigger.value.threshold, 0)
        metric_trigger_type = try(metric_trigger.value.metric_trigger_type, "Consecutive")
        metric_column       = try(metric_trigger.value.metric_column, null)
      }
    }
  }

  action {
    action_group = [for ag in local.all_action_groups : ag.action_group_id if contains(ag.severities, tonumber(each.value.severity))]
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]

    precondition {
      condition     = var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set when log query alerts are configured."
    }
  }
}

# ---------------------------------------------------------------------------
# Role assignments for v2 alerts with managed identity
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "log_alert" {
  for_each = { for idx, ra in local.all_log_alert_role_assignments : "${ra.source}-${ra.idx}" => ra }

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = azurerm_monitor_scheduled_query_rules_alert_v2.this[each.value.alert_key].identity[0].principal_id

  depends_on = [
    azurerm_monitor_scheduled_query_rules_alert_v2.this
  ]
}
