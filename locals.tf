locals {
  # Primary scope for query formatting (first entry in scopes list)
  primary_scope = var.scopes[0]

  # Unique subscription-scope IDs extracted from var.scopes. Used as for_each
  # key for health alerts so two scopes in the same subscription collapse to
  # one alert per category.
  health_alert_subscription_ids = toset([
    for s in var.scopes :
    regex("^/subscriptions/[0-9a-f-]+", lower(s))
  ])

  # Prefix folded into every alert description so PagerDuty incident titles
  # (which use the description) are customer-identifiable under the
  # one-service-per-solution model. Empty name_prefixes => no prefix.
  description_prefix = length(var.name_prefixes) > 0 ? format("[%s] ", split("-", var.name_prefixes[0])[0]) : ""
}

# ---------------------------------------------------------------------------
# Action group merging — unify external + module-created
# ---------------------------------------------------------------------------

locals {
  created_action_groups = [
    for key, ag in var.action_groups : {
      action_group_id = azurerm_monitor_action_group.this[key].id
      severities      = ag.severities
    }
  ]

  all_action_groups = concat(var.action_group_routing, local.created_action_groups)

  # Flat list of every action group ID, severity ignored — activity log alerts
  # (health alerts) do not carry a severity dimension so they notify all groups.
  health_alert_action_group_ids = distinct([for ag in local.all_action_groups : ag.action_group_id])
}

# ---------------------------------------------------------------------------
# Webhook receiver resolution — merge PagerDuty catalog lookups
# ---------------------------------------------------------------------------

locals {
  # For each webhook receiver: if pagerduty_key is set, substitute name and
  # service_uri from var.pagerduty_config. The precondition in
  # main.action_groups.tf guarantees every referenced key exists, so direct
  # map access here is safe.
  resolved_webhook_receivers = {
    for ag_key, ag in var.action_groups : ag_key => {
      for wh_key, wh in ag.webhook_receivers : wh_key => {
        name                    = wh.pagerduty_key != null ? format("PagerDuty %s", var.pagerduty_config[wh.pagerduty_key].name) : wh.name
        service_uri             = wh.pagerduty_key != null ? var.pagerduty_config[wh.pagerduty_key].webhook : wh.service_uri
        use_common_alert_schema = wh.use_common_alert_schema
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Default alert selection based on alert_profile
# NOTE: default_metric_alerts_by_profile and default_log_alerts_by_profile
# are auto-generated from YAML files in locals.defaults.tf
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Merge rules — apply defaults + configuration overrides + custom alerts
# ---------------------------------------------------------------------------

locals {
  # Format custom log alerts (substitute scope placeholder in queries)
  # Uses replace() instead of format() to avoid % being treated as format directive
  format_custom_log_alerts = { for alert, config in var.custom_log_alerts : alert => merge(config, {
    query = replace(config.query, "%%SCOPE%%", local.primary_scope)
  }) }

  # Compute which default metric alerts to apply
  # For appzone: opt-in — only rules explicitly present in configuration
  # For other profiles: opt-out — all rules unless disable_rule = true
  computed_default_metric_alerts = {
    for alert, cfg in try(local.default_metric_alerts_by_profile[var.alert_profile], {}) : alert => cfg
    if var.apply_default_rules && (
      (var.alert_profile != "appzone" && try(var.default_alert_rules_configuration[alert].disable_rule, false) != true) ||
      (var.alert_profile == "appzone" && contains(keys(var.default_alert_rules_configuration), alert))
    )
  }

  # Compute which default log alerts to apply (same opt-in/opt-out logic)
  apply_default_log_alerts = {
    for alert, config in try(local.default_log_alerts_by_profile[var.alert_profile], {}) : alert => config
    if var.apply_default_rules && (
      (var.alert_profile != "appzone" && try(var.default_alert_rules_configuration[alert].disable_rule, false) != true) ||
      (var.alert_profile == "appzone" && contains(keys(var.default_alert_rules_configuration), alert))
    )
  }
}

# ---------------------------------------------------------------------------
# Split log alerts into v1 (metric trigger) and v2 (standard)
# ---------------------------------------------------------------------------

locals {
  # Merged log alerts: defaults + custom
  all_log_alerts = merge(local.apply_default_log_alerts, local.format_custom_log_alerts)

  # v2: alerts WITHOUT metric_trigger — no nested metric_trigger object, no metric_trigger_type on trigger root
  merged_log_alerts_v2 = {
    for key, config in local.all_log_alerts : key => config
    if try(config.trigger.metric_trigger_type, null) == null && try(config.trigger.metric_trigger, null) == null
  }

  # v1: alerts WITH metric_trigger — either nested metric_trigger object or metric_trigger_type on trigger root
  merged_log_alerts_v1 = {
    for key, config in local.all_log_alerts : key => config
    if try(config.trigger.metric_trigger_type, null) != null || try(config.trigger.metric_trigger, null) != null
  }

  # Merged metric alerts: defaults + custom
  merged_metric_alerts = merge(local.computed_default_metric_alerts, var.custom_metric_alerts)
}

# ---------------------------------------------------------------------------
# Naming — standesamt provider functions
# ---------------------------------------------------------------------------

locals {
  log_alert_names_v2 = { for key, config in local.merged_log_alerts_v2 : key =>
    provider::standesamt::name(var.naming_configuration, "azurerm_monitor_scheduled_query_rules_alert", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = concat(var.name_suffixes, [format("sev%s", config.severity)])
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, config.name)
  }

  log_alert_names_v1 = { for key, config in local.merged_log_alerts_v1 : key =>
    provider::standesamt::name(var.naming_configuration, "azurerm_monitor_scheduled_query_rules_alert", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = concat(var.name_suffixes, [format("sev%s", config.severity)])
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, config.name)
  }

  metric_alert_names = { for key, config in local.merged_metric_alerts : key =>
    provider::standesamt::name(var.naming_configuration, "azurerm_monitor_metric_alert", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = concat(var.name_suffixes, [format("sev%s", config.severity)])
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, config.name)
  }

  action_group_names = { for key, config in var.action_groups : key =>
    provider::standesamt::name(var.naming_configuration, "azurerm_monitor_action_group", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = var.name_suffixes
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, key)
  }

  # Health alert names — one per subscription, suffixed with the subscription
  # GUID to avoid collisions when scopes span multiple subscriptions.
  service_health_alert_names = { for sub_id in local.health_alert_subscription_ids : sub_id =>
    provider::standesamt::name(var.naming_configuration, "azure_monitor_activity_log_alert", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = concat(var.name_suffixes, [split("/", sub_id)[2]])
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, var.health_alerts.service_health.name)
  }

  resource_health_alert_names = { for sub_id in local.health_alert_subscription_ids : sub_id =>
    provider::standesamt::name(var.naming_configuration, "azure_monitor_activity_log_alert", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = concat(var.name_suffixes, [split("/", sub_id)[2]])
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, var.health_alerts.resource_health.name)
  }

  _naming_configuration_custom = merge(
    var.naming_configuration,
    {
      schema = merge(
        try(var.naming_configuration_custom.schema, {}),
        try(var.naming_configuration.schema, {}),
      )
    }
  )

  alert_processing_rule_suppression_names = { for key, cfg in var.alert_processing_rule_suppressions : key =>
    provider::standesamt::name(local._naming_configuration_custom, "azurerm_monitor_alert_processing_rule_suppression", {
      convention      = var.convention
      location        = var.location
      environment     = var.environment
      prefixes        = var.name_prefixes
      suffixes        = var.name_suffixes
      name_precedence = var.name_precedence
      hash_length     = var.hash_length
    }, coalesce(cfg.name, key))
  }
}

# ---------------------------------------------------------------------------
# Role assignments for log alerts with managed identity
# ---------------------------------------------------------------------------

locals {
  # Custom log alert role assignments (v2 only — v1 doesn't support identity)
  custom_log_alert_role_assignments = flatten([
    for query, config in local.format_custom_log_alerts : concat(
      [
        for assignment in try(config.identity.role_assignments, []) : {
          scope                = assignment.scope
          role_definition_name = assignment.role_definition_name
          alert_key            = query
        }
      ],
      var.log_analytics_workspace_id != null ? [
        {
          scope                = var.log_analytics_workspace_id
          role_definition_name = "Reader"
          alert_key            = query
        }
      ] : []
    ) if(try(config.identity.enabled, false) == true || try(config.identity.enable, false) == true)
    && !can(regex("UserAssigned", try(config.identity.type, "SystemAssigned")))
    && contains(keys(local.merged_log_alerts_v2), query)
  ])

  # Default log alert role assignments (v2 only)
  default_log_alert_role_assignments = flatten([
    for query, config in local.apply_default_log_alerts : concat(
      [
        for assignment in try(config.identity.role_assignments, []) : {
          scope                = assignment.scope
          role_definition_name = assignment.role_definition_name
          alert_key            = query
        }
      ],
      [
        {
          scope                = local.primary_scope
          role_definition_name = "Reader"
          alert_key            = query
        }
      ],
      var.log_analytics_workspace_id != null ? [
        {
          scope                = var.log_analytics_workspace_id
          role_definition_name = "Reader"
          alert_key            = query
        }
      ] : []
    ) if(try(config.identity.enable, false) == true || try(config.identity.enabled, false) == true)
    && !can(regex("UserAssigned", try(config.identity.type, "SystemAssigned")))
    && contains(keys(local.merged_log_alerts_v2), query)
  ])

  all_log_alert_role_assignments = concat(
    [for idx, ra in local.custom_log_alert_role_assignments : merge(ra, { source = "custom", idx = idx })],
    [for idx, ra in local.default_log_alert_role_assignments : merge(ra, { source = "default", idx = idx })]
  )
}
