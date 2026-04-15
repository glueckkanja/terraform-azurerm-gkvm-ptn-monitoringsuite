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
  action_group_ids = [
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
