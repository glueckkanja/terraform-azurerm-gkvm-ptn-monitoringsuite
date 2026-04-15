output "metric_alerts" {
  description = "Map of created metric alert resources."
  value = {
    for key, alert in azurerm_monitor_metric_alert.this : key => {
      id       = alert.id
      name     = alert.name
      severity = alert.severity
    }
  }
}

output "log_alerts_v2" {
  description = "Map of created v2 log alert resources."
  value = {
    for key, alert in azurerm_monitor_scheduled_query_rules_alert_v2.this : key => {
      id       = alert.id
      name     = alert.name
      severity = alert.severity
    }
  }
}

output "log_alerts_v1" {
  description = "Map of created v1 log alert resources (metric trigger)."
  value = {
    for key, alert in azurerm_monitor_scheduled_query_rules_alert.this : key => {
      id       = alert.id
      name     = alert.name
      severity = alert.severity
    }
  }
}

output "action_groups" {
  description = "Map of module-created action group resources."
  value = {
    for key, ag in azurerm_monitor_action_group.this : key => {
      id   = ag.id
      name = ag.name
    }
  }
}

output "all_action_group_ids" {
  description = "Unified list of all action group IDs (external + module-created) with severity routing."
  value       = local.all_action_groups
}

output "alert_count" {
  description = "Count of created alerts by type."
  value = {
    metric_alerts    = length(azurerm_monitor_metric_alert.this)
    log_alerts_v2    = length(azurerm_monitor_scheduled_query_rules_alert_v2.this)
    log_alerts_v1    = length(azurerm_monitor_scheduled_query_rules_alert.this)
    action_groups    = length(azurerm_monitor_action_group.this)
    total            = length(azurerm_monitor_metric_alert.this) + length(azurerm_monitor_scheduled_query_rules_alert_v2.this) + length(azurerm_monitor_scheduled_query_rules_alert.this)
  }
}

output "warnings" {
  description = "Operational warnings. Check this output for potential configuration issues."
  value = compact([
    length(local.all_action_groups) == 0 ? "WARNING: No action groups configured. Alerts will fire but no notifications will be sent." : "",
    var.alert_profile != null && !contains(keys(local._raw_defaults), var.alert_profile) ? "WARNING: alert_profile '${var.alert_profile}' does not match any YAML file in defaults/. Zero default alerts will be created." : "",
  ])
}
