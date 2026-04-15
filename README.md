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
<!-- END_TF_DOCS -->
