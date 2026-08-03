# ---------------------------------------------------------------------------
# Health alerts — Service Health and Resource Health activity log alerts
#
# One alert per unique subscription extracted from var.scopes. Activity log
# alerts fire with a fixed Sev4 in the common alert schema, so they route
# through severity routing as Sev4: only action groups (external or
# module-created) whose severities include 4 receive notifications.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_activity_log_alert" "service_health" {
  for_each = var.health_alerts.service_health.enabled ? local.health_alert_subscription_ids : toset([])

  name                = local.service_health_alert_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.health_alerts.service_health.location

  scopes      = [each.value]
  description = format("%sService Health alert for subscription %s", local.description_prefix, split("/", each.value)[2])

  criteria {
    category = "ServiceHealth"
    statuses = var.health_alerts.service_health.statuses

    service_health {
      events    = var.health_alerts.service_health.events
      locations = var.health_alerts.service_health.locations
      services  = var.health_alerts.service_health.services
    }
  }

  dynamic "action" {
    for_each = local.health_alert_action_group_ids

    content {
      action_group_id = action.value
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_monitor_activity_log_alert" "resource_health" {
  for_each = var.health_alerts.resource_health.enabled ? local.health_alert_subscription_ids : toset([])

  name                = local.resource_health_alert_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.health_alerts.resource_health.location

  scopes      = [each.value]
  description = format("%sResource Health alert for subscription %s", local.description_prefix, split("/", each.value)[2])

  criteria {
    category = "ResourceHealth"
    statuses = var.health_alerts.resource_health.statuses

    dynamic "resource_health" {
      for_each = (
        try(var.health_alerts.resource_health.current, null) != null ||
        try(var.health_alerts.resource_health.previous, null) != null ||
        try(var.health_alerts.resource_health.reason, null) != null
      ) ? [1] : []

      content {
        current  = var.health_alerts.resource_health.current
        previous = var.health_alerts.resource_health.previous
        reason   = var.health_alerts.resource_health.reason
      }
    }
  }

  dynamic "action" {
    for_each = local.health_alert_action_group_ids

    content {
      action_group_id = action.value
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}
