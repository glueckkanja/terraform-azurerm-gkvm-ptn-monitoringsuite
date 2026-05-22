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

output "all_action_group_routing" {
  description = "Unified list of all action groups (external + module-created) with severity routing."
  value       = local.all_action_groups
}

output "service_health_alerts" {
  description = "Map of created Service Health activity log alerts, keyed by subscription scope."
  value = {
    for key, alert in azurerm_monitor_activity_log_alert.service_health : key => {
      id   = alert.id
      name = alert.name
    }
  }
}

output "resource_health_alerts" {
  description = "Map of created Resource Health activity log alerts, keyed by subscription scope."
  value = {
    for key, alert in azurerm_monitor_activity_log_alert.resource_health : key => {
      id   = alert.id
      name = alert.name
    }
  }
}

output "alert_processing_rule_suppressions" {
  description = "Map of created alert processing rule suppression resources."
  value = {
    for key, rule in azurerm_monitor_alert_processing_rule_suppression.this : key => {
      id      = rule.id
      name    = rule.name
      enabled = rule.enabled
    }
  }
}

output "alert_count" {
  description = "Count of created alerts by type."
  value = {
    metric_alerts                      = length(azurerm_monitor_metric_alert.this)
    log_alerts_v2                      = length(azurerm_monitor_scheduled_query_rules_alert_v2.this)
    log_alerts_v1                      = length(azurerm_monitor_scheduled_query_rules_alert.this)
    action_groups                      = length(azurerm_monitor_action_group.this)
    service_health_alerts              = length(azurerm_monitor_activity_log_alert.service_health)
    resource_health_alerts             = length(azurerm_monitor_activity_log_alert.resource_health)
    alert_processing_rule_suppressions = length(azurerm_monitor_alert_processing_rule_suppression.this)
    total = (
      length(azurerm_monitor_metric_alert.this) +
      length(azurerm_monitor_scheduled_query_rules_alert_v2.this) +
      length(azurerm_monitor_scheduled_query_rules_alert.this) +
      length(azurerm_monitor_activity_log_alert.service_health) +
      length(azurerm_monitor_activity_log_alert.resource_health) +
      length(azurerm_monitor_alert_processing_rule_suppression.this)
    )
  }
}

output "warnings" {
  description = "Operational warnings. Check this output for potential configuration issues."
  value = compact([
    length(local.all_action_groups) == 0 ? "WARNING: No action groups configured. Alerts will fire but no notifications will be sent." : "",
    var.alert_profile != null ? (!contains(keys(local._provider_defaults_substituted), var.alert_profile) ? "WARNING: alert_profile '${var.alert_profile}' not found in defaults_override. Zero default alerts will be created. Pass gkvm_monitoring_profiles.this.profiles via defaults_override." : "") : "",
    (var.health_alerts.service_health.enabled || var.health_alerts.resource_health.enabled) && length(local.health_alert_action_group_ids) == 0 ? "WARNING: Health alerts are enabled but no action groups are configured. Health events will be detected but no notifications will be sent." : "",
  ])
}
