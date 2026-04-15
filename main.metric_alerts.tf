resource "azurerm_monitor_metric_alert" "this" {
  for_each = local.merged_metric_alerts

  name                     = local.metric_alert_names[each.key]
  resource_group_name      = var.resource_group_name
  scopes                   = each.value.metric_namespace == "Microsoft.OperationalInsights/workspaces" ? [var.log_analytics_workspace_id] : var.scopes
  target_resource_type     = try(each.value.target_resource_type, null)
  target_resource_location = var.location
  description              = each.value.description
  enabled                  = try(each.value.enabled, true)

  frequency   = each.value.frequency
  window_size = each.value.window_size
  severity    = each.value.severity

  dynamic "criteria" {
    for_each = each.value.alert_criterias != null ? each.value.alert_criterias : []

    content {
      metric_namespace = each.value.metric_namespace
      metric_name      = try(criteria.value.metric_name, null)
      aggregation      = try(criteria.value.aggregation, null)
      operator         = try(criteria.value.operator, null)
      threshold        = try(criteria.value.threshold, null)

      dynamic "dimension" {
        for_each = try(criteria.value.dimensions, null) != null ? criteria.value.dimensions : []

        content {
          name     = try(dimension.value.name, null)
          operator = try(dimension.value.operator, null)
          values   = try(dimension.value.values, null)
        }
      }
    }
  }

  dynamic "action" {
    for_each = [for ag in local.all_action_groups : ag.action_group_id if contains(ag.severities, tonumber(each.value.severity))]

    content {
      action_group_id = action.value
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]

    precondition {
      condition     = each.value.metric_namespace != "Microsoft.OperationalInsights/workspaces" || var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be set for alerts targeting Microsoft.OperationalInsights/workspaces."
    }
  }
}
