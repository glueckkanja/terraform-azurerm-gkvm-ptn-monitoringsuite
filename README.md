# terraform-azurerm-gkvm-ptn-monitoringsuite

GKVM (glueckkanja Verified Module) for Azure Monitor alerting.

## Overview

This module provides a generalized, scope-based Azure monitoring alerting solution. It replaces the legacy `terraform-af-modules/monitoring/azure_monitor` module with a modernized design following AVM/GKVM conventions.

### Key features

- **Generalized scoping** -- `scopes` (list) + `alert_profile` instead of `resource_id` + `resource_type`
- **Hybrid action groups** -- pass external action groups AND/OR create new ones inside the module
- **Severity-based routing** -- action groups only receive alerts matching their configured severity levels
- **Default alert library** -- 13 built-in profiles with opt-in (appzone) or opt-out (all others) selection
- **v1 + v2 log alerts** -- v2 preferred; v1 retained for metric trigger patterns
- **Standesamt naming** -- consistent resource naming via provider-defined functions

## Usage

```hcl
data "standesamt_config" "this" {}

module "firewall_monitoring" {
  source = "glueckkanja/gkvm-ptn-monitoringsuite/azurerm"

  scopes              = [azurerm_firewall.this.id]
  alert_profile       = "firewall"
  location            = "westeurope"
  resource_group_name = azurerm_resource_group.monitoring.name

  action_group_ids = [
    {
      action_group_id = azurerm_monitor_action_group.critical.id
      severities      = [0, 1]
    },
    {
      action_group_id = azurerm_monitor_action_group.warning.id
      severities      = [2, 3, 4]
    }
  ]

  log_analytics_workspace_id       = azurerm_log_analytics_workspace.this.id
  log_analytics_workspace_location = azurerm_log_analytics_workspace.this.location

  naming_configuration = data.standesamt_config.this.configuration
  convention           = "default"
  environment          = "prod"

  tags = { environment = "prod" }
}
```

## Alert profiles

| Profile | Metric alerts | Log alerts | Description |
|---------|:---:|:---:|-------------|
| `appzone` | -- | 14 | Generalized application zone (web apps, functions, DBs, VMs, Logic Apps, update mgmt) |
| `application_gateway` | 2 | -- | Failed requests, unhealthy hosts |
| `application_insights` | 1 | -- | Dependency/server failures |
| `avd` | -- | 10 | Azure Virtual Desktop (session host health, connections, FSLogix, input delay, RDP latency) |
| `bastion_host` | 1 | -- | Communication status (pingmesh) |
| `dns_zone` | 1 | -- | Record set capacity |
| `express_route` | 7 | -- | ARP/BGP availability, bandwidth, gateway CPU |
| `firewall` | 5 | -- | App/net rule denies, SNAT utilization, health |
| `log_analytics_workspace` | -- | -- | Custom alerts only |
| `network_connection_monitor` | 1 | -- | Checks failed percent |
| `private_dns_zone` | 3 | -- | Record sets, VNet links, auto-registration |
| `virtual_machine` | 3 | -- | CPU, disk, memory |
| `virtual_network_gateway` | 1 | 1 | Bandwidth + VPN tunnel status |
| `vpn_gateway` | 2 | -- | S2S and P2S bandwidth |

### Appzone opt-in behavior

Unlike other profiles where all defaults are enabled (opt-out via `disable_rule`), the **appzone** profile uses **opt-in**: only rules explicitly present in `default_alert_rules_configuration` are created. This allows selective monitoring across a diverse application zone.

## Action groups

The module supports two sources of action groups that are merged internally:

1. **External** (`action_group_ids`) -- pre-existing action groups passed by ID
2. **Module-created** (`action_groups`) -- created inside the module with configurable receivers

Both use severity routing: each action group specifies which severity levels (0-4) it handles.

## Severity levels

| Level | Name | Typical use |
|:---:|---|---|
| 0 | Critical | Infrastructure down, data loss risk |
| 1 | Error | Service degradation, failures |
| 2 | Warning | Threshold breaches, capacity concerns |
| 3 | Informational | Notable events |
| 4 | Verbose | Debug-level alerts |

## Migration from terraform-af-modules

| Old module | New module |
|---|---|
| `resource_id` | `scopes = [resource_id]` |
| `resource_type = "azurerm_firewall"` | `alert_profile = "firewall"` |
| `resource_type = "appzone"` | `alert_profile = "appzone"` |
| `scope = ["vm-name"]` | Handled via query patterns in scopes |
| `action_group_ids` (required) | `action_group_ids` (optional) + `action_groups` (optional) |

## Requirements

| Name | Version |
|---|---|
| OpenTofu | >= 1.9, < 2.0 |
| azurerm | = 4.68.0 |
| standesamt | = 2.0.1 |
| modtm | = 0.3.5 |
| random | = 3.8.1 |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9, < 2.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.68.0, < 5.0 |
| <a name="requirement_modtm"></a> [modtm](#requirement\_modtm) | >= 0.3.5, < 1.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.8.1, < 4.0 |
| <a name="requirement_standesamt"></a> [standesamt](#requirement\_standesamt) | >= 2.0.1, < 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.68.0, < 5.0 |
| <a name="provider_modtm"></a> [modtm](#provider\_modtm) | >= 0.3.5, < 1.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.8.1, < 4.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_metric_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_role_assignment.log_alert](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [modtm_telemetry.telemetry](https://registry.terraform.io/providers/azure/modtm/latest/docs/resources/telemetry) | resource |
| [random_uuid.telemetry](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_action_group_routing"></a> [action\_group\_routing](#input\_action\_group\_routing) | External (pre-existing) action groups with severity-based routing. Each entry maps an action group ID to the severity levels (0=Critical … 4=Verbose) it should receive. Use action\_groups to create new action groups within this module. | <pre>list(object({<br/>    action_group_id = string<br/>    severities      = list(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_action_groups"></a> [action\_groups](#input\_action\_groups) | Action groups to create within the module. Each action group includes severity routing and one or more receiver types. | <pre>map(object({<br/>    short_name = string<br/>    severities = list(number)<br/>    enabled    = optional(bool, true)<br/><br/>    email_receivers = optional(map(object({<br/>      name                    = string<br/>      email_address           = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    webhook_receivers = optional(map(object({<br/>      name                    = string<br/>      service_uri             = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    sms_receivers = optional(map(object({<br/>      name         = string<br/>      country_code = string<br/>      phone_number = string<br/>    })), {})<br/><br/>    azure_app_push_receivers = optional(map(object({<br/>      name          = string<br/>      email_address = string<br/>    })), {})<br/><br/>    arm_role_receivers = optional(map(object({<br/>      name                    = string<br/>      role_id                 = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    logic_app_receivers = optional(map(object({<br/>      name                    = string<br/>      resource_id             = string<br/>      callback_url            = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    azure_function_receivers = optional(map(object({<br/>      name                     = string<br/>      function_app_resource_id = string<br/>      function_name            = string<br/>      http_trigger_url         = string<br/>      use_common_alert_schema  = optional(bool, true)<br/>    })), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_alert_profile"></a> [alert\_profile](#input\_alert\_profile) | Alert profile to apply default alerts for. Must match a profile name from built-in defaults or defaults\_override. Set to null to disable default alerts entirely. | `string` | `null` | no |
| <a name="input_apply_default_rules"></a> [apply\_default\_rules](#input\_apply\_default\_rules) | Enable default alert rules for the selected alert\_profile. Has no effect if alert\_profile is null. | `bool` | `true` | no |
| <a name="input_bandwidth"></a> [bandwidth](#input\_bandwidth) | Bandwidth threshold in bytes for VPN/ExpressRoute gateway monitoring. | `number` | `625000000` | no |
| <a name="input_convention"></a> [convention](#input\_convention) | Naming convention. Use 'passthrough' to skip convention and pass resource name through directly. | `string` | n/a | yes |
| <a name="input_custom_log_alerts"></a> [custom\_log\_alerts](#input\_custom\_log\_alerts) | Custom log query alerts. Keys are used as resource identifiers. Use %%SCOPE%% in query strings as placeholder for the primary scope (first entry in var.scopes). | <pre>map(object({<br/>    name                              = string<br/>    description                       = optional(string, "")<br/>    severity                          = number<br/>    time_window                       = optional(string, "PT15M")<br/>    frequency                         = optional(string, "PT5M")<br/>    query                             = string<br/>    mute_actions_after_alert_duration = optional(string)<br/>    auto_mitigation_enabled           = optional(bool, true)<br/>    time_aggregation_method           = optional(string, "Count")<br/>    metric_measure_column             = optional(string)<br/>    resource_id_column                = optional(string)<br/><br/>    dimensions = optional(list(object({<br/>      name     = string<br/>      operator = optional(string, "Include")<br/>      values   = list(string)<br/>    })), [])<br/><br/>    failing_periods = optional(object({<br/>      minimum_failing_periods_to_trigger_alert = optional(number, 1)<br/>      number_of_evaluation_periods             = optional(number, 1)<br/>    }))<br/><br/>    trigger = optional(object({<br/>      operator  = string<br/>      threshold = number<br/><br/>      metric_trigger = optional(object({<br/>        operator            = string<br/>        threshold           = number<br/>        metric_trigger_type = string<br/>        metric_column       = string<br/>      }))<br/>    }))<br/><br/>    identity = optional(object({<br/>      enabled = optional(bool, false)<br/>      type    = optional(string, "SystemAssigned")<br/>      role_assignments = optional(list(object({<br/>        role_definition_name = string<br/>        scope                = string<br/>      })), [])<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_metric_alerts"></a> [custom\_metric\_alerts](#input\_custom\_metric\_alerts) | Custom metric alerts. Keys are used as resource identifiers. | <pre>map(object({<br/>    name                 = string<br/>    description          = optional(string, "")<br/>    severity             = number<br/>    window_size          = optional(string, "PT15M")<br/>    frequency            = optional(string, "PT5M")<br/>    metric_namespace     = string<br/>    target_resource_type = optional(string)<br/>    enabled              = optional(bool, true)<br/><br/>    alert_criterias = list(object({<br/>      metric_name = string<br/>      operator    = string<br/>      aggregation = string<br/>      threshold   = number<br/><br/>      dimensions = optional(list(object({<br/>        name     = string<br/>        operator = optional(string, "Include")<br/>        values   = list(string)<br/>      })), [])<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_default_alert_rules_configuration"></a> [default\_alert\_rules\_configuration](#input\_default\_alert\_rules\_configuration) | Override individual default alert rules. Keys match default rule names. Supports: disable\_rule (bool), severity, threshold (for bandwidth-based alerts this is a multiplier 0.0-1.0, not absolute), window\_size, frequency, name, time\_aggregation\_method, metric\_measure\_column, mute\_actions\_after\_alert\_duration, auto\_mitigation\_enabled. | `any` | `{}` | no |
| <a name="input_defaults_override"></a> [defaults\_override](#input\_defaults\_override) | Map of profile\_name → JSON string from the gkvm provider data source (gkvm\_monitoring\_profiles). This is the sole source of default alert profiles. Each JSON string must contain {metric\_alerts: {...}, log\_alerts: {...}}. | `map(string)` | `{}` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Controls whether telemetry is enabled for the module.<br/>For more information see <https://aka.ms/avm/telemetryinfo>.<br/>If set to false, no telemetry will be collected. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used in resource naming (e.g., prod, dev, test). | `string` | n/a | yes |
| <a name="input_hash_length"></a> [hash\_length](#input\_hash\_length) | Hash length for resource naming. | `number` | `0` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for alert resources. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics Workspace resource ID. Required when using log query alerts. | `string` | `null` | no |
| <a name="input_log_analytics_workspace_location"></a> [log\_analytics\_workspace\_location](#input\_log\_analytics\_workspace\_location) | Log Analytics Workspace location. Required when using log query alerts. | `string` | `null` | no |
| <a name="input_name_precedence"></a> [name\_precedence](#input\_name\_precedence) | Name precedence rules for resource naming. | `list(string)` | `[]` | no |
| <a name="input_name_prefixes"></a> [name\_prefixes](#input\_name\_prefixes) | Name prefixes for resource naming. | `list(string)` | `[]` | no |
| <a name="input_name_suffixes"></a> [name\_suffixes](#input\_name\_suffixes) | Name suffixes for resource naming. | `list(string)` | `[]` | no |
| <a name="input_naming_configuration"></a> [naming\_configuration](#input\_naming\_configuration) | Standesamt naming configuration object. Obtained from the standesamt\_config data source. | `any` | n/a | yes |
| <a name="input_remote_ip"></a> [remote\_ip](#input\_remote\_ip) | Remote IP address for VPN tunnel monitoring. Used by virtual\_network\_gateway alert profile. | `string` | `""` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group where alert resources will be created. | `string` | n/a | yes |
| <a name="input_scopes"></a> [scopes](#input\_scopes) | List of Azure resource IDs to monitor. All alerts will target these scopes. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources created by this module. | `map(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_action_groups"></a> [action\_groups](#output\_action\_groups) | Map of module-created action group resources. |
| <a name="output_alert_count"></a> [alert\_count](#output\_alert\_count) | Count of created alerts by type. |
| <a name="output_all_action_group_routing"></a> [all\_action\_group\_routing](#output\_all\_action\_group\_routing) | Unified list of all action groups (external + module-created) with severity routing. |
| <a name="output_log_alerts_v1"></a> [log\_alerts\_v1](#output\_log\_alerts\_v1) | Map of created v1 log alert resources (metric trigger). |
| <a name="output_log_alerts_v2"></a> [log\_alerts\_v2](#output\_log\_alerts\_v2) | Map of created v2 log alert resources. |
| <a name="output_metric_alerts"></a> [metric\_alerts](#output\_metric\_alerts) | Map of created metric alert resources. |
| <a name="output_warnings"></a> [warnings](#output\_warnings) | Operational warnings. Check this output for potential configuration issues. |
<!-- END_TF_DOCS -->
