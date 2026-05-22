data "standesamt_config" "this" {}

# ---------------------------------------------------------------------------
# Load full alert profile library from gkvm provider (optional)
# Without this, only built-in basic profiles are available.
# With this, all 14+ profiles including appzone, AVD, express_route etc.
# ---------------------------------------------------------------------------

data "gkvm_monitoring_profiles" "this" {}

# ---------------------------------------------------------------------------
# Example 1: Firewall monitoring with external action group (built-in profile)
# ---------------------------------------------------------------------------

module "firewall_monitoring" {
  source = "../.."

  scopes              = [var.firewall_resource_id]
  alert_profile       = "firewall"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Provider-served defaults (includes all profiles — overrides built-in)
  defaults_override = data.gkvm_monitoring_profiles.this.profiles

  # External action group with severity routing
  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.Insights/actionGroups/ag-ops-critical"
      severities      = [0, 1]
    },
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.Insights/actionGroups/ag-ops-warning"
      severities      = [2, 3, 4]
    }
  ]

  log_analytics_workspace_id       = var.log_analytics_workspace_id
  log_analytics_workspace_location = var.log_analytics_workspace_location

  naming_configuration = data.standesamt_config.this.configuration
  convention           = "default"
  environment          = var.environment
  name_prefixes        = ["contoso"]

  tags = {
    environment = var.environment
    managed_by  = "opentofu"
  }
}

# ---------------------------------------------------------------------------
# Example 2: Appzone monitoring (provider profile — not in built-in defaults)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Example 3: Health alerts only — no metric/log alerts, PagerDuty routing
#
# Demonstrates the module deployed purely for Service Health + Resource Health
# monitoring at subscription scope, with notifications routed to PagerDuty
# via the pagerduty_config catalog.
# ---------------------------------------------------------------------------

module "subscription_health" {
  source = "../.."

  # Scope used solely to derive the subscription ID for health alerts.
  scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000"]

  # Alerting disabled — this deployment serves only health alerts.
  alert_profile       = null
  apply_default_rules = false

  location            = var.location
  resource_group_name = var.resource_group_name

  health_alerts = {
    service_health = {
      enabled   = true
      events    = ["Incident", "Maintenance", "Security"]
      locations = ["Global", "westeurope"]
    }
    resource_health = {
      enabled = true
      current = ["Degraded", "Unavailable"]
    }
  }

  # PagerDuty catalog — webhook URLs treated as secrets, sourced from a
  # sensitive variable in the caller.
  pagerduty_config = var.pagerduty_config

  # Route notifications through a module-managed action group that uses
  # PagerDuty via pagerduty_key.
  action_groups = {
    pager = {
      short_name = "pager"
      severities = [0, 1, 2, 3, 4]
      webhook_receivers = {
        primary = {
          pagerduty_key = "ops-primary"
        }
      }
    }
  }

  # Suppress resource health noise from VMs inside Databricks managed RGs.
  # Databricks automatically creates RGs with names containing "databricks-rg-".
  # Both sub-blocks are ANDed: only VMs within those RGs are suppressed, not all resources in them.
  alert_processing_rule_suppressions = {
    exclude_databricks_vms = {
      description = "Suppress resource health alerts for VMs inside Databricks managed resource groups"
      condition = {
        target_resource_group = {
          operator = "Contains"
          values   = ["databricks-rg-"]
        }
        target_resource_type = {
          operator = "Equals"
          values   = ["microsoft.compute/virtualmachines"]
        }
      }
    }
  }

  naming_configuration = data.standesamt_config.this.configuration
  convention           = "default"
  environment          = var.environment
  name_prefixes        = ["contoso"]

  tags = {
    environment = var.environment
    managed_by  = "opentofu"
  }
}

module "appzone_monitoring" {
  source = "../.."

  scopes              = [var.app_scope]
  alert_profile       = "appzone"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Required: appzone profile comes from the gkvm provider, not built-in
  defaults_override = data.gkvm_monitoring_profiles.this.profiles

  action_groups = {
    app_team = {
      short_name = "appteam"
      severities = [0, 1, 2]
      email_receivers = {
        lead = {
          name                    = "app-team-lead"
          email_address           = "app-lead@contoso.com"
          use_common_alert_schema = true
        }
      }
    }
  }

  # Appzone uses opt-in: only rules listed here are created
  default_alert_rules_configuration = {
    app_service_http_5xx = {
      threshold   = 50
      window_size = "PT30M"
    }
    virtual_machine_heartbeat = {}
    virtual_machine_disk_sev0 = {
      threshold = 3
    }
  }

  log_analytics_workspace_id       = var.log_analytics_workspace_id
  log_analytics_workspace_location = var.log_analytics_workspace_location

  naming_configuration = data.standesamt_config.this.configuration
  convention           = "default"
  environment          = var.environment
  name_prefixes        = ["contoso", "appzone"]

  tags = {
    environment = var.environment
    managed_by  = "opentofu"
  }
}
