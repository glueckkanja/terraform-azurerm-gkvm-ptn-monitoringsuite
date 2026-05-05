# -----------------------------------------------------------------------------
# Core variables
# -----------------------------------------------------------------------------

variable "scopes" {
  type        = list(string)
  description = "List of Azure resource IDs to monitor. All alerts will target these scopes. Subscription-only scopes ('/subscriptions/<guid>') are also accepted — useful when only health alerts are deployed."

  validation {
    condition     = length(var.scopes) > 0
    error_message = "At least one scope must be provided."
  }

  validation {
    condition = alltrue([
      for scope in var.scopes :
      can(regex("^/subscriptions/[0-9a-f-]+(/|$)", lower(scope)))
    ])
    error_message = "Each scope must be a valid Azure resource ID starting with /subscriptions/<subscription-id>."
  }
}

variable "alert_profile" {
  type        = string
  description = "Alert profile to apply default alerts for. Must match a profile name from built-in defaults or defaults_override. Set to null to disable default alerts entirely. Combined with apply_default_rules=false and empty custom_*_alerts this makes the alerting layer fully optional — e.g. when the module is deployed only for health alerts or only for action groups."
  default     = null
}

variable "defaults_override" {
  type        = map(string)
  default     = {}
  description = "Map of profile_name → JSON string from the gkvm provider data source (gkvm_monitoring_profiles). This is the sole source of default alert profiles. Each JSON string must contain {metric_alerts: {...}, log_alerts: {...}}."
}

variable "location" {
  type        = string
  description = "Azure region for alert resources."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group where alert resources will be created."
}

# -----------------------------------------------------------------------------
# Default alert configuration
# -----------------------------------------------------------------------------

variable "apply_default_rules" {
  type        = bool
  default     = true
  description = "Enable default alert rules for the selected alert_profile. Has no effect if alert_profile is null."
}

variable "default_alert_rules_configuration" {
  type        = any
  default     = {}
  description = "Override individual default alert rules. Keys match default rule names. Supports: disable_rule (bool), severity, threshold (for bandwidth-based alerts this is a multiplier 0.0-1.0, not absolute), window_size, frequency, name, time_aggregation_method, metric_measure_column, mute_actions_after_alert_duration, auto_mitigation_enabled."
}

# -----------------------------------------------------------------------------
# Custom alerts
# -----------------------------------------------------------------------------

variable "custom_log_alerts" {
  type = map(object({
    name                              = string
    description                       = optional(string, "")
    severity                          = number
    time_window                       = optional(string, "PT15M")
    frequency                         = optional(string, "PT5M")
    query                             = string
    mute_actions_after_alert_duration = optional(string)
    auto_mitigation_enabled           = optional(bool, true)
    time_aggregation_method           = optional(string, "Count")
    metric_measure_column             = optional(string)
    resource_id_column                = optional(string)

    dimensions = optional(list(object({
      name     = string
      operator = optional(string, "Include")
      values   = list(string)
    })), [])

    failing_periods = optional(object({
      minimum_failing_periods_to_trigger_alert = optional(number, 1)
      number_of_evaluation_periods             = optional(number, 1)
    }))

    trigger = optional(object({
      operator  = string
      threshold = number

      metric_trigger = optional(object({
        operator            = string
        threshold           = number
        metric_trigger_type = string
        metric_column       = string
      }))
    }))

    identity = optional(object({
      enabled = optional(bool, false)
      type    = optional(string, "SystemAssigned")
      role_assignments = optional(list(object({
        role_definition_name = string
        scope                = string
      })), [])
    }))
  }))
  default     = {}
  description = "Custom log query alerts. Keys are used as resource identifiers. Use %%SCOPE%% in query strings as placeholder for the primary scope (first entry in var.scopes)."
}

variable "custom_metric_alerts" {
  type = map(object({
    name                 = string
    description          = optional(string, "")
    severity             = number
    window_size          = optional(string, "PT15M")
    frequency            = optional(string, "PT5M")
    metric_namespace     = string
    target_resource_type = optional(string)
    enabled              = optional(bool, true)

    alert_criterias = list(object({
      metric_name = string
      operator    = string
      aggregation = string
      threshold   = number

      dimensions = optional(list(object({
        name     = string
        operator = optional(string, "Include")
        values   = list(string)
      })), [])
    }))
  }))
  default     = {}
  description = "Custom metric alerts. Keys are used as resource identifiers."
}

# -----------------------------------------------------------------------------
# Action groups — external (passed in)
# -----------------------------------------------------------------------------

variable "action_group_routing" {
  type = list(object({
    action_group_id = string
    severities      = list(number)
  }))
  default     = []
  description = "External (pre-existing) action groups with severity-based routing. Each entry maps an action group ID to the severity levels (0=Critical … 4=Verbose) it should receive. Use action_groups to create new action groups within this module."
}

# -----------------------------------------------------------------------------
# Action groups — module-created
# -----------------------------------------------------------------------------

variable "action_groups" {
  type = map(object({
    short_name = string
    severities = list(number)
    enabled    = optional(bool, true)

    email_receivers = optional(map(object({
      name                    = string
      email_address           = string
      use_common_alert_schema = optional(bool, true)
    })), {})

    webhook_receivers = optional(map(object({
      name                    = optional(string)
      service_uri             = optional(string)
      pagerduty_key           = optional(string)
      use_common_alert_schema = optional(bool, true)
    })), {})

    sms_receivers = optional(map(object({
      name         = string
      country_code = string
      phone_number = string
    })), {})

    azure_app_push_receivers = optional(map(object({
      name          = string
      email_address = string
    })), {})

    arm_role_receivers = optional(map(object({
      name                    = string
      role_id                 = string
      use_common_alert_schema = optional(bool, true)
    })), {})

    logic_app_receivers = optional(map(object({
      name                    = string
      resource_id             = string
      callback_url            = string
      use_common_alert_schema = optional(bool, true)
    })), {})

    azure_function_receivers = optional(map(object({
      name                     = string
      function_app_resource_id = string
      function_name            = string
      http_trigger_url         = string
      use_common_alert_schema  = optional(bool, true)
    })), {})
  }))
  default     = {}
  description = "Action groups to create within the module. Each action group includes severity routing and one or more receiver types."

  validation {
    condition = alltrue([
      for ag_key, ag in var.action_groups : alltrue([
        for wh_key, wh in ag.webhook_receivers :
        (wh.pagerduty_key != null) || (wh.service_uri != null && can(regex("^https://", wh.service_uri)))
      ])
    ])
    error_message = "Each webhook_receiver must set either pagerduty_key (resolved against var.pagerduty_config) or an https:// service_uri. Plaintext HTTP webhook endpoints are not permitted."
  }

  validation {
    condition = alltrue([
      for ag_key, ag in var.action_groups : alltrue([
        for wh_key, wh in ag.webhook_receivers :
        (wh.name != null && wh.name != "") || (wh.pagerduty_key != null)
      ])
    ])
    error_message = "Each webhook_receiver must have a name, unless pagerduty_key is set (in which case the name is derived from pagerduty_config)."
  }

  validation {
    condition = alltrue([
      for ag_key, ag in var.action_groups : alltrue([
        for la_key, la in ag.logic_app_receivers :
        can(regex("^https://", la.callback_url))
      ])
    ])
    error_message = "All logic_app_receiver callback_url values must use HTTPS."
  }

  validation {
    condition = alltrue([
      for ag_key, ag in var.action_groups : alltrue([
        for fn_key, fn in ag.azure_function_receivers :
        can(regex("^https://", fn.http_trigger_url))
      ])
    ])
    error_message = "All azure_function_receiver http_trigger_url values must use HTTPS."
  }
}

# -----------------------------------------------------------------------------
# PagerDuty — optional webhook endpoint catalog
# -----------------------------------------------------------------------------

variable "pagerduty_config" {
  type = map(object({
    name    = string
    webhook = string
  }))
  default     = {}
  sensitive   = true
  description = "PagerDuty endpoint catalog. When a webhook_receiver sets pagerduty_key, the receiver's service_uri is set to pagerduty_config[pagerduty_key].webhook and its name is set to 'PagerDuty <name>'. Marked sensitive to prevent webhook URLs from appearing in plan output."

  validation {
    condition = alltrue([
      for k, v in var.pagerduty_config :
      can(regex("^https://", v.webhook))
    ])
    error_message = "All pagerduty_config[].webhook URLs must use HTTPS."
  }

  validation {
    condition = alltrue([
      for k, v in var.pagerduty_config :
      v.name != null && v.name != ""
    ])
    error_message = "All pagerduty_config[].name values must be non-empty."
  }
}

# -----------------------------------------------------------------------------
# Health alerts — Service Health and Resource Health activity-log alerts
# -----------------------------------------------------------------------------

variable "health_alerts" {
  type = object({
    service_health = optional(object({
      enabled   = optional(bool, false)
      name      = optional(string, "servicehealth")
      location  = optional(string, "Global")
      events    = optional(list(string), ["Incident", "Maintenance", "Informational", "ActionRequired", "Security"])
      locations = optional(list(string), ["Global"])
      services  = optional(list(string))
      statuses  = optional(list(string))
    }), {})
    resource_health = optional(object({
      enabled  = optional(bool, false)
      name     = optional(string, "resourcehealth")
      location = optional(string, "Global")
      statuses = optional(list(string))
      current  = optional(list(string))
      previous = optional(list(string))
      reason   = optional(list(string))
    }), {})
  })
  default     = {}
  description = "Service Health and Resource Health activity log alerts. One alert is created per unique subscription extracted from var.scopes. All action groups (external and module-created) receive notifications; severity routing does not apply to activity log alerts. Set service_health.enabled or resource_health.enabled to true to deploy. Field mapping: service_health.events/locations/services → criteria.service_health block; resource_health.current/previous/reason → criteria.resource_health block."

  validation {
    condition = alltrue([
      for e in(var.health_alerts.service_health.events == null ? [] : var.health_alerts.service_health.events) :
      contains(["Incident", "Maintenance", "Informational", "ActionRequired", "Security"], e)
    ])
    error_message = "service_health.events must be a subset of: Incident, Maintenance, Informational, ActionRequired, Security."
  }

  validation {
    condition = alltrue([
      for s in concat(
        var.health_alerts.resource_health.current == null ? [] : var.health_alerts.resource_health.current,
        var.health_alerts.resource_health.previous == null ? [] : var.health_alerts.resource_health.previous,
      ) :
      contains(["Available", "Degraded", "Unavailable", "Unknown"], s)
    ])
    error_message = "resource_health.current / resource_health.previous must be a subset of: Available, Degraded, Unavailable, Unknown."
  }

  validation {
    condition = alltrue([
      for r in(var.health_alerts.resource_health.reason == null ? [] : var.health_alerts.resource_health.reason) :
      contains(["PlatformInitiated", "UserInitiated", "Unknown"], r)
    ])
    error_message = "resource_health.reason must be a subset of: PlatformInitiated, UserInitiated, Unknown."
  }

  validation {
    condition = alltrue([
      for s in concat(
        var.health_alerts.service_health.statuses == null ? [] : var.health_alerts.service_health.statuses,
        var.health_alerts.resource_health.statuses == null ? [] : var.health_alerts.resource_health.statuses,
      ) :
      contains(["Active", "In Progress", "Resolved", "Updated"], s)
    ])
    error_message = "*.statuses must be a subset of activity log event statuses: Active, In Progress, Resolved, Updated."
  }
}

# -----------------------------------------------------------------------------
# Log Analytics Workspace
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Log Analytics Workspace resource ID. Required when using log query alerts."
}

variable "log_analytics_workspace_location" {
  type        = string
  default     = null
  description = "Log Analytics Workspace location. Required when using log query alerts."
}

# -----------------------------------------------------------------------------
# Profile-specific optional variables
# -----------------------------------------------------------------------------

variable "remote_ip" {
  type        = string
  default     = ""
  description = "Remote IP address for VPN tunnel monitoring. Used by virtual_network_gateway alert profile."
}

variable "bandwidth" {
  type        = number
  default     = 625000000
  description = "Bandwidth threshold in bytes for VPN/ExpressRoute gateway monitoring."
}

# -----------------------------------------------------------------------------
# Standard GKVM variables
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = null
  description = "Tags applied to all resources created by this module."
}

variable "enable_telemetry" {
  type        = bool
  default     = false
  nullable    = false
  description = <<-DESCRIPTION
    Controls whether telemetry is enabled for the module.
    For more information see <https://aka.ms/avm/telemetryinfo>.
    If set to false, no telemetry will be collected.
  DESCRIPTION
}

# NOTE: lock and diagnostic_settings planned for Phase 1.1 — not yet implemented
