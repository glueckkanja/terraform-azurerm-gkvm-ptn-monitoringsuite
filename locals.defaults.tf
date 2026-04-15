# ---------------------------------------------------------------------------
# Default alert library loader
#
# Two sources, merged with override taking precedence:
# 1. Built-in: YAML files in defaults/*.yaml (shipped with module)
# 2. Provider: var.defaults_override from gkvm_monitoring_profiles data source
#
# YAML/JSON schema:
#   metric_alerts:
#     <rule_key>:
#       name, description, severity, window_size, frequency, metric_namespace
#       bandwidth_multiplier (optional): multiply threshold by var.bandwidth
#       alert_criterias: [{ metric_name, operator, aggregation, threshold, dimensions? }]
#   log_alerts:
#     <rule_key>:
#       name, description, severity, time_window, frequency
#       query_template: KQL with ${primary_scope}, ${remote_ip} interpolation
#       trigger: { operator, threshold, metric_trigger_type? }
#       time_aggregation_method, metric_measure_column?, dimensions?, identity?
# ---------------------------------------------------------------------------

locals {
  # -------------------------------------------------------------------------
  # Source 1: Built-in YAML defaults (shipped with module — basic profiles)
  # -------------------------------------------------------------------------
  _default_alert_files = fileset("${path.module}/defaults", "*.yaml")

  _template_vars = {
    primary_scope = local.primary_scope
    remote_ip     = var.remote_ip
    bandwidth     = var.bandwidth
  }

  _builtin_defaults = {
    for file in local._default_alert_files :
    trimsuffix(file, ".yaml") => yamldecode(
      templatefile("${path.module}/defaults/${file}", local._template_vars)
    )
  }

  # -------------------------------------------------------------------------
  # Source 2: Provider-served defaults (from gkvm_monitoring_profiles)
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
            replace(replace(replace(
              rule.query_template,
              "$${primary_scope}", local.primary_scope),
              "$${remote_ip}", var.remote_ip),
              "$${bandwidth}", tostring(var.bandwidth)),
            try(rule.query_template, "")
          )
        })
      }
    }
  }

  # -------------------------------------------------------------------------
  # Merge: provider overrides built-in (same profile name → provider wins)
  # -------------------------------------------------------------------------
  _raw_defaults = merge(local._builtin_defaults, local._provider_defaults_substituted)

  # -------------------------------------------------------------------------
  # Metric alerts: apply config overrides (name, severity, threshold, etc.)
  # -------------------------------------------------------------------------
  _loaded_metric_alerts = {
    for profile, data in local._raw_defaults : profile => {
      for rule_key, rule in try(data.metric_alerts, {}) : rule_key => merge(rule, {
        name        = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "name", rule.name)
        severity    = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "severity", rule.severity)
        window_size = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "window_size", rule.window_size)
        frequency   = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "frequency", rule.frequency)

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
    for profile, data in local._raw_defaults : profile => {
      for rule_key, rule in try(data.log_alerts, {}) : rule_key => merge(rule, {
        name                              = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "name", rule.name)
        severity                          = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "severity", rule.severity)
        time_window                       = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "window_size", try(rule.time_window, "PT15M"))
        frequency                         = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "frequency", try(rule.frequency, "PT5M"))
        mute_actions_after_alert_duration = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "mute_actions_after_alert_duration", try(rule.mute_actions_after_alert_duration, null))
        auto_mitigation_enabled           = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "auto_mitigation_enabled", try(rule.auto_mitigation_enabled, null))
        time_aggregation_method           = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "time_aggregation_method", try(rule.time_aggregation_method, "Count"))
        metric_measure_column             = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "metric_measure_column", try(rule.metric_measure_column, null))

        # query_template has variables substituted (by templatefile for built-in, by replace for provider)
        query = try(rule.query_template, try(rule.query, ""))

        trigger = merge(try(rule.trigger, {}), {
          threshold = lookup(try(var.default_alert_rules_configuration[rule_key], {}), "threshold", try(rule.trigger.threshold, 0))
        })
      })
    }
  }
}

# ---------------------------------------------------------------------------
# Expose per-profile maps consumed by locals.tf lookup tables
# ---------------------------------------------------------------------------

locals {
  default_metric_alerts_by_profile = local._loaded_metric_alerts
  default_log_alerts_by_profile    = local._loaded_log_alerts
}
