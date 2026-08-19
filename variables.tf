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
  # Explicitly typed rather than `any`: an `any`-typed map of mixed-shape objects is
  # unified by OpenTofu to map(map(string)), which stringifies every field — a bool
  # `disable_rule = true` arrives as "true" and silently stops matching. The object
  # schema converts per attribute instead, so each field keeps the type it was written as.
  # Unrecognised field names are still dropped silently (object conversion is permissive).
  type = map(object({
    disable_rule                      = optional(bool, false)
    name                              = optional(string)
    severity                          = optional(number)
    threshold                         = optional(number)
    window_size                       = optional(string)
    frequency                         = optional(string)
    time_aggregation_method           = optional(string)
    metric_measure_column             = optional(string)
    mute_actions_after_alert_duration = optional(string)
    auto_mitigation_enabled           = optional(bool)
    action_group_ids                  = optional(list(string))
  }))
  default     = {}
  description = "Override individual default alert rules. Keys match default rule names. Supported fields: disable_rule (bool), severity (number), threshold (number — for bandwidth-based alerts this is a multiplier 0.0-1.0, not absolute), window_size, frequency, name, time_aggregation_method, metric_measure_column, mute_actions_after_alert_duration, auto_mitigation_enabled (bool, defaults to true — stateful, one alert per episode; forced off when mute_actions_after_alert_duration is set or the rule is evaluated less often than every 12 hours), action_group_ids (list of action group resource IDs — when set, bypasses severity-based routing for that rule). Fields set to null and unrecognised field names are ignored and fall back to the rule's default, so typed consumer objects with optional(..., null) fields are safe to pass through."
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
      enabled      = optional(bool, false)
      type         = optional(string, "SystemAssigned")
      identity_ids = optional(list(string), [])
      role_assignments = optional(list(object({
        role_definition_name = string
        scope                = string
      })), [])
    }))

    action_group_ids = optional(list(string))
  }))
  default     = {}
  description = "Custom log query alerts. Keys are used as resource identifiers. Use %%SCOPE%% in query strings as placeholder for the primary scope (first entry in var.scopes). Set action_group_ids to bypass severity-based routing and notify only the specified action groups. Set identity.enabled = true to run the query as a managed identity — required for cross-resource queries such as adx() (Fabric Eventhouse), workspace() across subscriptions, or arg(). When using type = \"UserAssigned\" or \"SystemAssigned, UserAssigned\", set identity.identity_ids to the UAMI resource IDs. The UAMI must already hold the required permissions on the queried external resources — this module does not create role assignments for user-assigned identities."
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

    action_group_ids = optional(list(string))
  }))
  default     = {}
  description = "Custom metric alerts. Keys are used as resource identifiers. Set action_group_ids to bypass severity-based routing and notify only the specified action groups."
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
  description = "Service Health and Resource Health activity log alerts. One alert is created per unique subscription extracted from var.scopes. Activity log alerts fire with a fixed Sev4 in the common alert schema and route through severity routing accordingly: only action groups (external and module-created) whose severities include 4 receive notifications. Set service_health.enabled or resource_health.enabled to true to deploy. Field mapping: service_health.events/locations/services → criteria.service_health block; resource_health.current/previous/reason → criteria.resource_health block."

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

variable "adx_cluster_uri" {
  type        = string
  default     = ""
  description = "ADX or Fabric Eventhouse cluster URI substituted into query templates via the $${adx_cluster_uri} placeholder. Required when using an alert profile that queries an ADX cluster or Fabric Eventhouse."
}

variable "fabric_capacity_id" {
  type        = string
  default     = ""
  description = "Fabric capacity ID substituted into query templates via the $${fabric_capacity_id} placeholder. Required when using an alert profile that references a specific Fabric capacity."
}

variable "fabric_workspace_id" {
  type        = string
  default     = ""
  description = "Fabric workspace ID substituted into query templates via the $${fabric_workspace_id} placeholder. Required when using an alert profile that references a specific Fabric workspace."
}

variable "namespace" {
  type        = string
  default     = null
  description = "Kubernetes namespace to scope kubernetes_workload log alerts to, via the $${namespace_filter} placeholder. Leave null for cluster-wide alerts. Only valid with alert_profile = \"kubernetes_workload\"."

  validation {
    condition     = var.namespace == null || can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid Kubernetes namespace name (RFC 1123 label: lowercase alphanumeric and '-', max 63 chars)."
  }

  validation {
    condition     = var.namespace == null || var.alert_profile == "kubernetes_workload"
    error_message = "namespace is only valid when alert_profile = \"kubernetes_workload\"."
  }
}

variable "data_lake_deletion_exclusions" {
  type = list(object({
    paths      = list(string)
    object_ids = optional(list(string), [])
  }))
  default     = []
  description = "Exclusion rules for the data_lake container-deletion and directory-deletion alerts. A deletion is suppressed if it matches any rule: its StorageBlobLogs ObjectKey contains one of paths (has_any) AND, when object_ids is set, its RequesterObjectId is one of object_ids (e.g. the Databricks Access Connector managed identity). object_ids only narrows a path scope. Empty default = no exclusion."

  validation {
    condition     = alltrue([for ex in var.data_lake_deletion_exclusions : length(ex.paths) > 0])
    error_message = "Each data_lake_deletion_exclusions entry must list at least one path (object_ids alone suppress nothing)."
  }

  validation {
    condition     = alltrue([for ex in var.data_lake_deletion_exclusions : alltrue([for p in ex.paths : trimspace(p) != ""])])
    error_message = "Path entries must not be empty or whitespace-only. An empty path in has_any can match all rows, silently suppressing all deletion alerts."
  }
}

variable "default_log_alert_identity_ids" {
  type        = list(string)
  default     = []
  description = "UAMI resource IDs applied to all default log alerts that have no identity block in their profile definition. Use this to run cross-resource queries (e.g. adx() to a Fabric Eventhouse) as a specific identity. Has no effect on alerts that already declare an identity in the YAML, on custom_log_alerts, or when left empty."
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

# -----------------------------------------------------------------------------
# Alert processing rules — suppression
# -----------------------------------------------------------------------------

variable "alert_processing_rule_suppressions" {
  type = map(object({
    name        = optional(string)
    description = optional(string, "")
    enabled     = optional(bool, true)
    scopes      = optional(list(string))
    condition = optional(object({
      alert_context         = optional(object({ operator = string, values = list(string) }))
      alert_rule_id         = optional(object({ operator = string, values = list(string) }))
      alert_rule_name       = optional(object({ operator = string, values = list(string) }))
      description           = optional(object({ operator = string, values = list(string) }))
      monitor_condition     = optional(object({ operator = string, values = list(string) }))
      monitor_service       = optional(object({ operator = string, values = list(string) }))
      severity              = optional(object({ operator = string, values = list(string) }))
      signal_type           = optional(object({ operator = string, values = list(string) }))
      target_resource       = optional(object({ operator = string, values = list(string) }))
      target_resource_group = optional(object({ operator = string, values = list(string) }))
      target_resource_type  = optional(object({ operator = string, values = list(string) }))
    }))
    schedule = optional(object({
      effective_from  = optional(string)
      effective_until = optional(string)
      time_zone       = optional(string, "UTC")
      recurrence = optional(object({
        daily = optional(list(object({
          start_time = string
          end_time   = string
        })), [])
        weekly = optional(list(object({
          days_of_week = list(string)
          start_time   = optional(string)
          end_time     = optional(string)
        })), [])
        monthly = optional(list(object({
          days_of_month = list(number)
          start_time    = optional(string)
          end_time      = optional(string)
        })), [])
      }))
    }))
    tags = optional(map(string))
  }))
  default     = {}
  description = "Alert processing rules of type 'suppression'. Each entry creates one azurerm_monitor_alert_processing_rule_suppression scoped to this module's subscriptions. Use to silence alerts by target_resource_type (e.g. 'microsoft.compute/virtualmachines'), target_resource_group (e.g. Databricks managed RGs), severity, alert_rule_id, alert_rule_name, or any other condition dimension. Leave scopes null to inherit var.scopes. At least one of condition or schedule must be set per rule."

  validation {
    condition = alltrue([
      for key, rule in var.alert_processing_rule_suppressions :
      rule.schedule != null || (
        rule.condition != null && anytrue([
          try(rule.condition.alert_context, null) != null,
          try(rule.condition.alert_rule_id, null) != null,
          try(rule.condition.alert_rule_name, null) != null,
          try(rule.condition.description, null) != null,
          try(rule.condition.monitor_condition, null) != null,
          try(rule.condition.monitor_service, null) != null,
          try(rule.condition.severity, null) != null,
          try(rule.condition.signal_type, null) != null,
          try(rule.condition.target_resource, null) != null,
          try(rule.condition.target_resource_group, null) != null,
          try(rule.condition.target_resource_type, null) != null,
        ])
      )
    ])
    error_message = "Each alert_processing_rule_suppressions entry must set at least one of: schedule, or condition with at least one condition sub-block (e.g. severity, target_resource_type). An empty condition = {} with no sub-blocks would suppress all alerts at scope unconditionally."
  }

  validation {
    condition = alltrue([
      for key, rule in var.alert_processing_rule_suppressions :
      rule.condition == null ? true : alltrue([
        for op in compact([
          try(rule.condition.alert_context.operator, null),
          try(rule.condition.alert_rule_id.operator, null),
          try(rule.condition.alert_rule_name.operator, null),
          try(rule.condition.description.operator, null),
          try(rule.condition.monitor_condition.operator, null),
          try(rule.condition.monitor_service.operator, null),
          try(rule.condition.severity.operator, null),
          try(rule.condition.signal_type.operator, null),
          try(rule.condition.target_resource.operator, null),
          try(rule.condition.target_resource_group.operator, null),
          try(rule.condition.target_resource_type.operator, null),
        ]) :
        contains(["Equals", "NotEquals", "Contains", "DoesNotContain"], op)
      ])
    ])
    error_message = "Each condition sub-block operator must be one of: Equals, NotEquals, Contains, DoesNotContain."
  }
}
