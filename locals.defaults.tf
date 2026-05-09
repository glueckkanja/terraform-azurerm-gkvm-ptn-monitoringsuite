# ---------------------------------------------------------------------------
# Default alert library loader
#
# Single source: var.defaults_override from gkvm_monitoring_profiles data source
# (JSON strings → parsed maps, with template variable substitution via replace())
#
# YAML/JSON schema expected in each profile:
#   metric_alerts:
#     <rule_key>:
#       name, description, severity, window_size, frequency, metric_namespace
#       bandwidth_multiplier (optional): multiply threshold by var.bandwidth
#       alert_criterias: [{ metric_name, operator, aggregation, threshold, dimensions? }]
#   log_alerts:
#     <rule_key>:
#       name, description, severity, time_window, frequency
#       query_template: KQL with ${primary_scope}, ${remote_ip}, ${bandwidth}, ${eventhouse_uri} interpolation
#       trigger: { operator, threshold, metric_trigger_type? }
#       time_aggregation_method, metric_measure_column?, dimensions?, identity?
#   (action_group_ids is injected at merge time from var.default_alert_rules_configuration)
# ---------------------------------------------------------------------------

locals {
  # -------------------------------------------------------------------------
  # Provider-served defaults (from gkvm_monitoring_profiles)
  # JSON strings → parsed maps, with template variable substitution via replace()
  # -------------------------------------------------------------------------
  _provider_defaults = {
    for name, json_str in var.defaults_override : name => jsondecode(json_str)
  }

  # Substitute template variables in provider-served query_template strings
  # Provider returns raw strings with literal ${primary_scope} etc.
  _provider_defaults_substituted = {
    for profile, data in local._provider_defaults : profile => {
      metric_alerts = try(data.metric_alerts, {})
      log_alerts = {
        for rule_key, rule in try(data.log_alerts, {}) : rule_key => merge(rule, {
          query_template = try(
            replace(replace(replace(replace(
              rule.query_template,
              "$${primary_scope}", local.primary_scope),
              "$${remote_ip}", var.remote_ip),
              "$${bandwidth}", tostring(var.bandwidth)),
            "$${eventhouse_uri}", var.eventhouse_uri),
            try(rule.query_template, "")
          )
        })
      }
    }
  }

  # -------------------------------------------------------------------------
  # Metric alerts: apply config overrides (name, severity, threshold, etc.)
  # -------------------------------------------------------------------------
  _loaded_metric_alerts = {
    for profile, data in local._provider_defaults_substituted : profile => {
      for rule_key, rule in try(data.metric_alerts, {}) : rule_key => merge(rule, {
        name             = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "name", rule.name)
        severity         = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "severity", rule.severity)
        window_size      = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "window_size", rule.window_size)
        frequency        = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "frequency", rule.frequency)
        action_group_ids = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "action_group_ids", null)

        alert_criterias = [
          for c in try(rule.alert_criterias, []) : merge(c, {
            threshold = try(rule.bandwidth_multiplier, null) != null ? (
              var.bandwidth * lookup(try(var.default_alert_rules_configuration[rule_key], {}), "threshold", c.threshold)
            ) : lookup(try(var.default_alert_rules_configuration[rule_key], {}), "threshold", c.threshold)
          })
        ]
      })
    }
  }

  # -------------------------------------------------------------------------
  # Log alerts: apply config overrides + resolve query_template → query
  # -------------------------------------------------------------------------
  _loaded_log_alerts = {
    for profile, data in local._provider_defaults_substituted : profile => {
      for rule_key, rule in try(data.log_alerts, {}) : rule_key => merge(rule, {
        name                              = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "name", rule.name)
        severity                          = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "severity", rule.severity)
        time_window                       = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "window_size", try(rule.time_window, "PT15M"))
        frequency                         = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "frequency", try(rule.frequency, "PT5M"))
        mute_actions_after_alert_duration = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "mute_actions_after_alert_duration", try(rule.mute_actions_after_alert_duration, null))
        auto_mitigation_enabled           = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "auto_mitigation_enabled", try(rule.auto_mitigation_enabled, null))
        time_aggregation_method           = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "time_aggregation_method", try(rule.time_aggregation_method, "Count"))
        metric_measure_column             = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "metric_measure_column", try(rule.metric_measure_column, null))
        action_group_ids                  = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "action_group_ids", null)

        # query_template has template variables substituted via replace() above
        query = try(rule.query_template, try(rule.query, ""))

        trigger = merge(try(rule.trigger, {}), {
          threshold = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "threshold", try(rule.trigger.threshold, 0))
        })

        # Pass through only the YAML-defined identity so the alert config remains fully
        # known at plan time. UAMI injection is deferred to the resource level via
        # _log_alert_injected_identity, which keeps its known-after-apply identity_ids
        # out of the for_each map computation.
        identity = try(rule.identity, null) != null ? {
          enabled      = try(rule.identity.enabled, true)
          type         = rule.identity.type
          identity_ids = try(rule.identity.identity_ids, null)
        } : null
      })
    }
  }
}

locals {
  # Single computed identity to inject into default log alerts that have no YAML-defined
  # identity block. Kept outside the per-alert for loop so "known after apply" identity_ids
  # (e.g. a newly-created UAMI) do not contaminate the for_each map keys.
  _log_alert_injected_identity = length(var.default_log_alert_identity_ids) > 0 ? {
    enabled      = true
    type         = "UserAssigned"
    identity_ids = var.default_log_alert_identity_ids
  } : null
}

# ---------------------------------------------------------------------------
# Expose per-profile maps consumed by locals.tf lookup tables
# ---------------------------------------------------------------------------

locals {
  default_metric_alerts_by_profile = local._loaded_metric_alerts
  default_log_alerts_by_profile    = local._loaded_log_alerts
}
