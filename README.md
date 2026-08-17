# terraform-azurerm-gkvm-ptn-monitoringsuite

GKVM (glueckkanja Verified Module) for Azure Monitor alerting.

## Overview

This module provides a generalized, scope-based Azure monitoring alerting solution. It replaces the legacy `terraform-af-modules/monitoring/azure_monitor` module with a modernized design following AVM/GKVM conventions.

### Key features

- **Generalized scoping** -- `scopes` (list) + `alert_profile` instead of `resource_id` + `resource_type`
- **Optional alerting** -- deploy the module solely for action groups and/or health alerts by setting `alert_profile = null`, `apply_default_rules = false`, and passing no `custom_*_alerts`
- **Hybrid action groups** -- pass external action groups AND/OR create new ones inside the module
- **Severity-based routing** -- action groups only receive alerts matching their configured severity levels
- **Per-alert action group override** -- set `action_group_ids` on any custom alert or default rule override to bypass severity routing and notify only the specified groups
- **Default alert library** -- 13 built-in profiles with opt-in (appzone) or opt-out (all others) selection
- **v1 + v2 log alerts** -- v2 preferred; v1 retained for metric trigger patterns
- **Health alerts** -- Service Health and Resource Health activity log alerts at subscription scope, derived from `scopes`
- **PagerDuty catalog** -- resolve webhook URLs through a central `pagerduty_config` map; never leaked in plan diffs
- **Standesamt naming** -- consistent resource naming via provider-defined functions
- **Alert processing rules** -- suppress alerts by condition (resource type, resource group, severity, signal type, and more) and/or schedule; supports one-time and recurring maintenance windows

## Usage

```hcl
data "standesamt_config" "this" {}

module "firewall_monitoring" {
  source = "glueckkanja/gkvm-ptn-monitoringsuite/azurerm"

  scopes              = [azurerm_firewall.this.id]
  alert_profile       = "firewall"
  location            = "westeurope"
  resource_group_name = azurerm_resource_group.monitoring.name

  action_group_routing = [
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

### Appzone opt-in behavior

Unlike other profiles where all defaults are enabled (opt-out via `disable_rule`), the **appzone** profile uses **opt-in**: only rules explicitly present in `default_alert_rules_configuration` are created. This allows selective monitoring across a diverse application zone.

## Action groups

The module supports two sources of action groups that are merged internally:

1. **External** (`action_group_routing`) -- pre-existing action groups passed by ID
2. **Module-created** (`action_groups`) -- created inside the module with configurable receivers

Both use severity routing: each action group specifies which severity levels (0-4) it handles.

### Per-alert action group override

When severity routing is too coarse — for example, a specific alert should notify only the customer and not the MSP — set `action_group_ids` directly on the alert. This bypasses severity routing for that alert and routes notifications exclusively to the listed action group resource IDs. All other alerts continue to use the global severity routing.

```hcl
# Customer group is still defined globally
action_group_routing = [
  { action_group_id = azurerm_monitor_action_group.msp.id,      severities = [0, 1, 2, 3, 4] },
  { action_group_id = azurerm_monitor_action_group.customer.id, severities = [2, 3, 4] }
]

# This specific alert goes only to the customer, regardless of severity
custom_metric_alerts = {
  customer_capacity = {
    name             = "Customer Capacity Alert"
    severity         = 2
    metric_namespace = "Microsoft.Network/azureFirewalls"
    alert_criterias  = [{ metric_name = "Throughput", operator = "GreaterThan", aggregation = "Average", threshold = 1000 }]
    action_group_ids = [azurerm_monitor_action_group.customer.id]
  }
}

# Same override works for default alert rules
default_alert_rules_configuration = {
  fw_health = {
    action_group_ids = [azurerm_monitor_action_group.customer.id]
  }
}
```

### Alert description prefixes

When using `name_prefixes`, the module automatically prepends a customer-identifiable prefix to all alert descriptions. This is especially useful in the one-service-per-solution MSP model where PagerDuty incident titles (derived from alert descriptions) must immediately identify which customer's environment is being alerted.

The prefix is derived from the first element of `name_prefixes`, taking only the part before the first `-`. This means a monitoring key like `CUST-PROD` produces the prefix `[CUST]`:

```hcl
name_prefixes = ["CUST-PROD"]

# Metric alert description becomes: "[CUST] Firewall health"
# Log alert description becomes: "[CUST] High memory usage"
# Service Health alert becomes: "[CUST] Service Health alert for subscription ..."
# Resource Health alert becomes: "[CUST] Resource Health alert for subscription ..."
```

If `name_prefixes` is empty or not provided, no prefix is added to descriptions.

### PagerDuty routing

Pass a catalog of PagerDuty integrations via `pagerduty_config` and reference catalog entries from individual webhook receivers using `pagerduty_key`. The module substitutes the receiver `name` and `service_uri` from the catalog entry. `pagerduty_config` is marked `sensitive`, so webhook URLs do not appear in plan output.

```hcl
pagerduty_config = {
  ops-primary = {
    name    = "ops-primary"
    webhook = "https://events.pagerduty.com/integration/.../enqueue"
  }
}

action_groups = {
  pager = {
    short_name = "pager"
    severities = [0, 1, 2]
    webhook_receivers = {
      primary = { pagerduty_key = "ops-primary" }
    }
  }
}
```

## Health alerts

Service Health and Resource Health activity log alerts are deployed at subscription scope. Subscription IDs are derived from `var.scopes`; one alert is created per unique subscription, so multiple scopes within the same subscription collapse to a single alert. A bare `/subscriptions/<guid>` scope is sufficient for health-alert-only deployments. Activity log alerts fire with a fixed **Sev4** in the common alert schema, so they route through severity routing like any other Sev4 alert: only action groups — external or module-created — whose `severities` include `4` receive the notifications. This keeps paging policies intact (a Sev0-only PagerDuty group is never paged by health events); route health alerts to a ticket-oriented group by adding `4` to its severities.

```hcl
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
```

## Managed identity for log alerts

By default, log alert v2 rules query the bound Log Analytics Workspace using Azure Monitor's
own access — no managed identity is required for standard single-workspace queries.

A managed identity is needed when the KQL query reaches outside the LAW, for example:

- `adx("https://...")` — querying a Fabric Eventhouse or ADX cluster
- `workspace("other-ws")` — cross-workspace queries to a LAW in another resource group or subscription
- `arg("")` — querying Azure Resource Graph

In these cases, Azure Monitor has no implicit access to the external resource and the alert
must authenticate as an identity that has been granted access there.

Set `identity.enabled = true` on any `custom_log_alerts` entry and specify the identity type:

```hcl
custom_log_alerts = {
  fabric_query_alert = {
    name     = "fabric-kql-alert"
    severity = 2
    query    = "adx(\"https://<cluster>.kusto.fabric.microsoft.com/<DatabaseName>\").TableName | ..."
    identity = {
      enabled      = true
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.fabric.id]
    }
  }
}
```

Supported values for `type`: `"SystemAssigned"`, `"UserAssigned"`, `"SystemAssigned, UserAssigned"`.

> **Prerequisite:** This module does not create role assignments for user-assigned managed
> identities. Grant the UAMI the permissions required by its queries on the target resources
> before attaching it — for example Viewer on the Eventhouse database for `adx()` queries.
> Role assignments for system-assigned identities are still managed automatically by this module.

## Alert processing rules

Alert processing rules of type suppression prevent matched alerts from dispatching notifications to action groups. The underlying alert rule continues to evaluate — only the delivery of notifications is suppressed. Use them to eliminate known-benign alerts (for example, transient resource health blips during Databricks provisioning) or to silence alerts during planned maintenance windows.

```hcl
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

  sunday_patching_window = {
    description = "Suppress all alerts during Sunday patching window"
    schedule = {
      time_zone = "W. Europe Standard Time"
      recurrence = {
        weekly = [
          {
            days_of_week = ["Sunday"]
            start_time   = "02:00:00"
            end_time     = "06:00:00"
          }
        ]
      }
    }
  }
}
```

Available condition dimensions: `alert_context`, `alert_rule_id`, `alert_rule_name`, `description`, `monitor_condition`, `monitor_service`, `severity`, `signal_type`, `target_resource`, `target_resource_group`, `target_resource_type`. Each dimension takes `operator` and `values`. Valid operators: `"Equals"`, `"NotEquals"`, `"Contains"`, `"DoesNotContain"`.

When multiple condition sub-blocks are set on one rule, all must match (AND semantics). To suppress alerts matching either of two independent conditions, use two separate rules.

Leave `scopes` null on an entry to inherit `var.scopes`. An empty `condition = {}` with no sub-blocks is rejected by validation — at least one condition dimension or a `schedule` must be set per rule.

## Default alert profile template variables

Provider-served alert profiles may use the following placeholders in `query_template` strings.
The module substitutes them at plan time:

| Placeholder | Variable | Purpose |
| --- | --- | --- |
| `${primary_scope}` | _(derived from `var.scopes[0]`)_ | Resource ID of the primary monitored resource |
| `${adx_cluster_uri}` | `var.adx_cluster_uri` | ADX or Fabric Eventhouse cluster URI for `adx()` queries |
| `${fabric_capacity_id}` | `var.fabric_capacity_id` | Fabric capacity ID for capacity-scoped Fabric alerts |
| `${fabric_workspace_id}` | `var.fabric_workspace_id` | Fabric workspace ID for workspace-scoped Fabric alerts |
| `${remote_ip}` | `var.remote_ip` | Remote IP for VPN tunnel monitoring |
| `${bandwidth}` | `var.bandwidth` | Bandwidth threshold in bytes |
| `${data_lake_deletion_exclusion_predicate}` | `var.data_lake_deletion_exclusions` (generated) | Generated KQL predicate that excludes known-expected deletions from the data lake deletion alerts |
| `${namespace_filter}` | `var.namespace` (generated) | Generated KQL predicate that scopes `kubernetes_workload` log alerts to a single Kubernetes namespace; renders to `true` (cluster-wide) when `var.namespace` is unset |

These placeholders apply only to default profiles served by `var.defaults_override`.
Custom log alerts (`var.custom_log_alerts`) use `%%SCOPE%%` as a scope placeholder in their `query` field.

### Data lake deletion alerts

The `data_lake` profile ships two deletion log alerts, differentiated by blast radius:

| Alert | Severity | Threshold | Trigger condition |
| --- | --- | --- | --- |
| `default_container_deletion` | 1 (Error) | > 0 per window | Any non-excluded `DeleteContainer` operation |
| `default_directory_deletion` | 2 (Warning) | > 50 per 5-minute window | Non-excluded `DeleteDirectory` operations exceeding volume threshold |

Container deletion is high-blast-radius and fires immediately on any non-excluded event. Directory deletion tolerates routine single-table drops (for example, Databricks `DROP TABLE`) and fires only when volume indicates mass deletion.

#### Exclusion mechanism

Both alerts share a predicate built from `var.data_lake_deletion_exclusions` — a list of rules, each containing:

- `paths` — one or more path terms; a deletion is a candidate for exclusion if its `ObjectKey` contains any of these terms
- `object_ids` — an optional list of Azure AD object IDs; when provided, the path match is further narrowed to requests from those identities

A deletion is suppressed only when it matches a rule: the `ObjectKey` must contain a matching path term, and — when `object_ids` is non-empty — the requester's `RequesterObjectId` must be in the list. Providing `object_ids` without `paths` suppresses nothing; object IDs only narrow a path match.

The module generates a KQL predicate string from these rules and substitutes it into both deletion alert queries as `${data_lake_deletion_exclusion_predicate}`.

#### Example: excluding Databricks staging operations

```hcl
data_lake_deletion_exclusions = [
  {
    # Suppress alerts for all deletions under the Databricks staging database path
    paths = ["staging_db"]
  },
  {
    # Suppress alerts for the ETL pipeline path, scoped to the Access Connector's managed identity
    paths      = ["etl_pipeline"]
    object_ids = ["00000000-0000-0000-0000-000000000000"]
  }
]
```

The first rule suppresses any deletion whose `ObjectKey` contains `staging_db`, regardless of requester identity. The second rule suppresses `etl_pipeline` deletions only when the requester matches the specified managed identity. All other deletions continue to trigger alerts normally.

#### Recoverability

If the storage account has blob soft delete, container soft delete, or versioning enabled, deleted data remains recoverable within the retention period. Treat these alerts as notices requiring investigation rather than emergencies in that case.

### Namespace-scoped kubernetes_workload alerts

The `kubernetes_workload` profile's log alerts (pod CrashLoopBackOff, OOMKilled, unavailable deployments, pending pods) are cluster-wide by default. Set `var.namespace` to scope them to one Kubernetes namespace instead — the module folds the namespace into the generated `${namespace_filter}` KQL predicate, the alert name (so instances don't collide), and the description (so PagerDuty incident titles identify the namespace).

`namespace` is only accepted when `alert_profile = "kubernetes_workload"` — setting it on any other profile fails at plan time, since namespace scoping has no meaning outside a container context.

To monitor several namespaces, deploy one module instance per namespace with `for_each`:

```hcl
locals {
  monitored_namespaces = ["team-a", "team-b"]
}

module "aks_namespace_alerts" {
  source   = "glueckkanja/gkvm-ptn-monitoringsuite/azurerm"
  for_each = toset(local.monitored_namespaces)

  scopes        = [azurerm_kubernetes_cluster.this.id]
  alert_profile = "kubernetes_workload"
  namespace     = each.key

  # ... location, resource_group_name, naming_configuration, etc.
}
```

Each instance creates its own set of log alert rules — four scheduled query rules per namespace — so cost scales linearly with namespace count.

## Severity levels

| Level | Name          | Typical use                           |
| :---: | ------------- | ------------------------------------- |
|   0   | Critical      | Infrastructure down, data loss risk   |
|   1   | Error         | Service degradation, failures         |
|   2   | Warning       | Threshold breaches, capacity concerns |
|   3   | Informational | Notable events                        |
|   4   | Verbose       | Debug-level alerts                    |

## Migration from terraform-af-modules

| Old module                           | New module                                                 |
| ------------------------------------ | ---------------------------------------------------------- |
| `resource_id`                        | `scopes = [resource_id]`                                   |
| `resource_type = "azurerm_firewall"` | `alert_profile = "firewall"`                               |
| `resource_type = "appzone"`          | `alert_profile = "appzone"`                                |
| `scope = ["vm-name"]`                | Handled via query patterns in scopes                       |
| `action_group_routing` (was required)    | `action_group_routing` (optional) + `action_groups` (optional) |

## Requirements

| Name       | Version       |
| ---------- | ------------- |
| OpenTofu   | >= 1.9, < 2.0 |
| azurerm    | = 4.68.0      |
| standesamt | = 2.0.1       |
| modtm      | = 0.3.5       |
| random     | = 3.8.1       |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9, < 2.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.68.0, < 5.0 |
| <a name="requirement_modtm"></a> [modtm](#requirement\_modtm) | >= 0.3.5, < 1.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.8.1, < 4.0 |
| <a name="requirement_standesamt"></a> [standesamt](#requirement\_standesamt) | >= 2.0.1, < 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.68.0, < 5.0 |
| <a name="provider_modtm"></a> [modtm](#provider\_modtm) | >= 0.3.5, < 1.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.8.1, < 4.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_activity_log_alert.resource_health](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_activity_log_alert.service_health](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_alert_processing_rule_suppression.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_alert_processing_rule_suppression) | resource |
| [azurerm_monitor_metric_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [azurerm_role_assignment.log_alert](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [modtm_telemetry.telemetry](https://registry.terraform.io/providers/azure/modtm/latest/docs/resources/telemetry) | resource |
| [random_uuid.telemetry](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_action_group_routing"></a> [action\_group\_routing](#input\_action\_group\_routing) | External (pre-existing) action groups with severity-based routing. Each entry maps an action group ID to the severity levels (0=Critical … 4=Verbose) it should receive. Use action\_groups to create new action groups within this module. | <pre>list(object({<br/>    action_group_id = string<br/>    severities      = list(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_action_groups"></a> [action\_groups](#input\_action\_groups) | Action groups to create within the module. Each action group includes severity routing and one or more receiver types. | <pre>map(object({<br/>    short_name = string<br/>    severities = list(number)<br/>    enabled    = optional(bool, true)<br/><br/>    email_receivers = optional(map(object({<br/>      name                    = string<br/>      email_address           = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    webhook_receivers = optional(map(object({<br/>      name                    = optional(string)<br/>      service_uri             = optional(string)<br/>      pagerduty_key           = optional(string)<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    sms_receivers = optional(map(object({<br/>      name         = string<br/>      country_code = string<br/>      phone_number = string<br/>    })), {})<br/><br/>    azure_app_push_receivers = optional(map(object({<br/>      name          = string<br/>      email_address = string<br/>    })), {})<br/><br/>    arm_role_receivers = optional(map(object({<br/>      name                    = string<br/>      role_id                 = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    logic_app_receivers = optional(map(object({<br/>      name                    = string<br/>      resource_id             = string<br/>      callback_url            = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), {})<br/><br/>    azure_function_receivers = optional(map(object({<br/>      name                     = string<br/>      function_app_resource_id = string<br/>      function_name            = string<br/>      http_trigger_url         = string<br/>      use_common_alert_schema  = optional(bool, true)<br/>    })), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_adx_cluster_uri"></a> [adx\_cluster\_uri](#input\_adx\_cluster\_uri) | ADX or Fabric Eventhouse cluster URI substituted into query templates via the ${adx\_cluster\_uri} placeholder. Required when using an alert profile that queries an ADX cluster or Fabric Eventhouse. | `string` | `""` | no |
| <a name="input_alert_processing_rule_suppressions"></a> [alert\_processing\_rule\_suppressions](#input\_alert\_processing\_rule\_suppressions) | Alert processing rules of type 'suppression'. Each entry creates one azurerm\_monitor\_alert\_processing\_rule\_suppression scoped to this module's subscriptions. Use to silence alerts by target\_resource\_type (e.g. 'microsoft.compute/virtualmachines'), target\_resource\_group (e.g. Databricks managed RGs), severity, alert\_rule\_id, alert\_rule\_name, or any other condition dimension. Leave scopes null to inherit var.scopes. At least one of condition or schedule must be set per rule. | <pre>map(object({<br/>    name        = optional(string)<br/>    description = optional(string, "")<br/>    enabled     = optional(bool, true)<br/>    scopes      = optional(list(string))<br/>    condition = optional(object({<br/>      alert_context         = optional(object({ operator = string, values = list(string) }))<br/>      alert_rule_id         = optional(object({ operator = string, values = list(string) }))<br/>      alert_rule_name       = optional(object({ operator = string, values = list(string) }))<br/>      description           = optional(object({ operator = string, values = list(string) }))<br/>      monitor_condition     = optional(object({ operator = string, values = list(string) }))<br/>      monitor_service       = optional(object({ operator = string, values = list(string) }))<br/>      severity              = optional(object({ operator = string, values = list(string) }))<br/>      signal_type           = optional(object({ operator = string, values = list(string) }))<br/>      target_resource       = optional(object({ operator = string, values = list(string) }))<br/>      target_resource_group = optional(object({ operator = string, values = list(string) }))<br/>      target_resource_type  = optional(object({ operator = string, values = list(string) }))<br/>    }))<br/>    schedule = optional(object({<br/>      effective_from  = optional(string)<br/>      effective_until = optional(string)<br/>      time_zone       = optional(string, "UTC")<br/>      recurrence = optional(object({<br/>        daily = optional(list(object({<br/>          start_time = string<br/>          end_time   = string<br/>        })), [])<br/>        weekly = optional(list(object({<br/>          days_of_week = list(string)<br/>          start_time   = optional(string)<br/>          end_time     = optional(string)<br/>        })), [])<br/>        monthly = optional(list(object({<br/>          days_of_month = list(number)<br/>          start_time    = optional(string)<br/>          end_time      = optional(string)<br/>        })), [])<br/>      }))<br/>    }))<br/>    tags = optional(map(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_alert_profile"></a> [alert\_profile](#input\_alert\_profile) | Alert profile to apply default alerts for. Must match a profile name from built-in defaults or defaults\_override. Set to null to disable default alerts entirely. Combined with apply\_default\_rules=false and empty custom\_*\_alerts this makes the alerting layer fully optional — e.g. when the module is deployed only for health alerts or only for action groups. | `string` | `null` | no |
| <a name="input_apply_default_rules"></a> [apply\_default\_rules](#input\_apply\_default\_rules) | Enable default alert rules for the selected alert\_profile. Has no effect if alert\_profile is null. | `bool` | `true` | no |
| <a name="input_bandwidth"></a> [bandwidth](#input\_bandwidth) | Bandwidth threshold in bytes for VPN/ExpressRoute gateway monitoring. | `number` | `625000000` | no |
| <a name="input_convention"></a> [convention](#input\_convention) | Naming convention. Use 'passthrough' to skip convention and pass resource name through directly. | `string` | n/a | yes |
| <a name="input_custom_log_alerts"></a> [custom\_log\_alerts](#input\_custom\_log\_alerts) | Custom log query alerts. Keys are used as resource identifiers. Use %%SCOPE%% in query strings as placeholder for the primary scope (first entry in var.scopes). Set action\_group\_ids to bypass severity-based routing and notify only the specified action groups. Set identity.enabled = true to run the query as a managed identity — required for cross-resource queries such as adx() (Fabric Eventhouse), workspace() across subscriptions, or arg(). When using type = "UserAssigned" or "SystemAssigned, UserAssigned", set identity.identity\_ids to the UAMI resource IDs. The UAMI must already hold the required permissions on the queried external resources — this module does not create role assignments for user-assigned identities. | <pre>map(object({<br/>    name                              = string<br/>    description                       = optional(string, "")<br/>    severity                          = number<br/>    time_window                       = optional(string, "PT15M")<br/>    frequency                         = optional(string, "PT5M")<br/>    query                             = string<br/>    mute_actions_after_alert_duration = optional(string)<br/>    auto_mitigation_enabled           = optional(bool, true)<br/>    time_aggregation_method           = optional(string, "Count")<br/>    metric_measure_column             = optional(string)<br/>    resource_id_column                = optional(string)<br/><br/>    dimensions = optional(list(object({<br/>      name     = string<br/>      operator = optional(string, "Include")<br/>      values   = list(string)<br/>    })), [])<br/><br/>    failing_periods = optional(object({<br/>      minimum_failing_periods_to_trigger_alert = optional(number, 1)<br/>      number_of_evaluation_periods             = optional(number, 1)<br/>    }))<br/><br/>    trigger = optional(object({<br/>      operator  = string<br/>      threshold = number<br/><br/>      metric_trigger = optional(object({<br/>        operator            = string<br/>        threshold           = number<br/>        metric_trigger_type = string<br/>        metric_column       = string<br/>      }))<br/>    }))<br/><br/>    identity = optional(object({<br/>      enabled      = optional(bool, false)<br/>      type         = optional(string, "SystemAssigned")<br/>      identity_ids = optional(list(string), [])<br/>      role_assignments = optional(list(object({<br/>        role_definition_name = string<br/>        scope                = string<br/>      })), [])<br/>    }))<br/><br/>    action_group_ids = optional(list(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_metric_alerts"></a> [custom\_metric\_alerts](#input\_custom\_metric\_alerts) | Custom metric alerts. Keys are used as resource identifiers. Set action\_group\_ids to bypass severity-based routing and notify only the specified action groups. | <pre>map(object({<br/>    name                 = string<br/>    description          = optional(string, "")<br/>    severity             = number<br/>    window_size          = optional(string, "PT15M")<br/>    frequency            = optional(string, "PT5M")<br/>    metric_namespace     = string<br/>    target_resource_type = optional(string)<br/>    enabled              = optional(bool, true)<br/><br/>    alert_criterias = list(object({<br/>      metric_name = string<br/>      operator    = string<br/>      aggregation = string<br/>      threshold   = number<br/><br/>      dimensions = optional(list(object({<br/>        name     = string<br/>        operator = optional(string, "Include")<br/>        values   = list(string)<br/>      })), [])<br/>    }))<br/><br/>    action_group_ids = optional(list(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_data_lake_deletion_exclusions"></a> [data\_lake\_deletion\_exclusions](#input\_data\_lake\_deletion\_exclusions) | Exclusion rules for the data\_lake container-deletion and directory-deletion alerts. A deletion is suppressed if it matches any rule: its StorageBlobLogs ObjectKey contains one of paths (has\_any) AND, when object\_ids is set, its RequesterObjectId is one of object\_ids (e.g. the Databricks Access Connector managed identity). object\_ids only narrows a path scope. Empty default = no exclusion. | <pre>list(object({<br/>    paths      = list(string)<br/>    object_ids = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_default_alert_rules_configuration"></a> [default\_alert\_rules\_configuration](#input\_default\_alert\_rules\_configuration) | Override individual default alert rules. Keys match default rule names. Supports: disable\_rule (bool), severity, threshold (for bandwidth-based alerts this is a multiplier 0.0-1.0, not absolute), window\_size, frequency, name, time\_aggregation\_method, metric\_measure\_column, mute\_actions\_after\_alert\_duration, auto\_mitigation\_enabled, action\_group\_ids (list of action group resource IDs — when set, bypasses severity-based routing for that rule). | `any` | `{}` | no |
| <a name="input_default_log_alert_identity_ids"></a> [default\_log\_alert\_identity\_ids](#input\_default\_log\_alert\_identity\_ids) | UAMI resource IDs applied to all default log alerts that have no identity block in their profile definition. Use this to run cross-resource queries (e.g. adx() to a Fabric Eventhouse) as a specific identity. Has no effect on alerts that already declare an identity in the YAML, on custom\_log\_alerts, or when left empty. | `list(string)` | `[]` | no |
| <a name="input_defaults_override"></a> [defaults\_override](#input\_defaults\_override) | Map of profile\_name → JSON string from the gkvm provider data source (gkvm\_monitoring\_profiles). This is the sole source of default alert profiles. Each JSON string must contain {metric\_alerts: {...}, log\_alerts: {...}}. | `map(string)` | `{}` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Controls whether telemetry is enabled for the module.<br/>For more information see <https://aka.ms/avm/telemetryinfo>.<br/>If set to false, no telemetry will be collected. | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name used in resource naming (e.g., prod, dev, test). | `string` | n/a | yes |
| <a name="input_fabric_capacity_id"></a> [fabric\_capacity\_id](#input\_fabric\_capacity\_id) | Fabric capacity ID substituted into query templates via the ${fabric\_capacity\_id} placeholder. Required when using an alert profile that references a specific Fabric capacity. | `string` | `""` | no |
| <a name="input_fabric_workspace_id"></a> [fabric\_workspace\_id](#input\_fabric\_workspace\_id) | Fabric workspace ID substituted into query templates via the ${fabric\_workspace\_id} placeholder. Required when using an alert profile that references a specific Fabric workspace. | `string` | `""` | no |
| <a name="input_hash_length"></a> [hash\_length](#input\_hash\_length) | Hash length for resource naming. | `number` | `0` | no |
| <a name="input_health_alerts"></a> [health\_alerts](#input\_health\_alerts) | Service Health and Resource Health activity log alerts. One alert is created per unique subscription extracted from var.scopes. Activity log alerts fire with a fixed Sev4 in the common alert schema and route through severity routing accordingly: only action groups (external and module-created) whose severities include 4 receive notifications. Set service\_health.enabled or resource\_health.enabled to true to deploy. Field mapping: service\_health.events/locations/services → criteria.service\_health block; resource\_health.current/previous/reason → criteria.resource\_health block. | <pre>object({<br/>    service_health = optional(object({<br/>      enabled   = optional(bool, false)<br/>      name      = optional(string, "servicehealth")<br/>      location  = optional(string, "Global")<br/>      events    = optional(list(string), ["Incident", "Maintenance", "Informational", "ActionRequired", "Security"])<br/>      locations = optional(list(string), ["Global"])<br/>      services  = optional(list(string))<br/>      statuses  = optional(list(string))<br/>    }), {})<br/>    resource_health = optional(object({<br/>      enabled  = optional(bool, false)<br/>      name     = optional(string, "resourcehealth")<br/>      location = optional(string, "Global")<br/>      statuses = optional(list(string))<br/>      current  = optional(list(string))<br/>      previous = optional(list(string))<br/>      reason   = optional(list(string))<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for alert resources. | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics Workspace resource ID. Required when using log query alerts. | `string` | `null` | no |
| <a name="input_log_analytics_workspace_location"></a> [log\_analytics\_workspace\_location](#input\_log\_analytics\_workspace\_location) | Log Analytics Workspace location. Required when using log query alerts. | `string` | `null` | no |
| <a name="input_name_precedence"></a> [name\_precedence](#input\_name\_precedence) | Name precedence rules for resource naming. | `list(string)` | `[]` | no |
| <a name="input_name_prefixes"></a> [name\_prefixes](#input\_name\_prefixes) | Name prefixes for resource naming. | `list(string)` | `[]` | no |
| <a name="input_name_suffixes"></a> [name\_suffixes](#input\_name\_suffixes) | Name suffixes for resource naming. | `list(string)` | `[]` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Kubernetes namespace to scope kubernetes\_workload log alerts to, via the ${namespace\_filter} placeholder. Leave null for cluster-wide alerts. Only valid with alert\_profile = "kubernetes\_workload". | `string` | `null` | no |
| <a name="input_naming_configuration"></a> [naming\_configuration](#input\_naming\_configuration) | Standesamt naming configuration object. Obtained from the standesamt\_config data source. | `any` | n/a | yes |
| <a name="input_naming_configuration_custom"></a> [naming\_configuration\_custom](#input\_naming\_configuration\_custom) | Optional standesamt naming configuration produced by a standesamt\_config data source whose provider loads a custom schema (custom\_url). Supplies naming for resource types absent from the azure/caf library (e.g. azurerm\_monitor\_alert\_processing\_rule\_suppression). Its schema entries are merged under var.naming\_configuration; the normal naming schema wins on conflict. | `any` | `null` | no |
| <a name="input_pagerduty_config"></a> [pagerduty\_config](#input\_pagerduty\_config) | PagerDuty endpoint catalog. When a webhook\_receiver sets pagerduty\_key, the receiver's service\_uri is set to pagerduty\_config[pagerduty\_key].webhook and its name is set to 'PagerDuty <name>'. Marked sensitive to prevent webhook URLs from appearing in plan output. | <pre>map(object({<br/>    name    = string<br/>    webhook = string<br/>  }))</pre> | `{}` | no |
| <a name="input_remote_ip"></a> [remote\_ip](#input\_remote\_ip) | Remote IP address for VPN tunnel monitoring. Used by virtual\_network\_gateway alert profile. | `string` | `""` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group where alert resources will be created. | `string` | n/a | yes |
| <a name="input_scopes"></a> [scopes](#input\_scopes) | List of Azure resource IDs to monitor. All alerts will target these scopes. Subscription-only scopes ('/subscriptions/<guid>') are also accepted — useful when only health alerts are deployed. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all resources created by this module. | `map(string)` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_action_groups"></a> [action\_groups](#output\_action\_groups) | Map of module-created action group resources. |
| <a name="output_alert_count"></a> [alert\_count](#output\_alert\_count) | Count of created alerts by type. |
| <a name="output_alert_processing_rule_suppressions"></a> [alert\_processing\_rule\_suppressions](#output\_alert\_processing\_rule\_suppressions) | Map of created alert processing rule suppression resources. |
| <a name="output_all_action_group_routing"></a> [all\_action\_group\_routing](#output\_all\_action\_group\_routing) | Unified list of all action groups (external + module-created) with severity routing. |
| <a name="output_log_alerts_v1"></a> [log\_alerts\_v1](#output\_log\_alerts\_v1) | Map of created v1 log alert resources (metric trigger). |
| <a name="output_log_alerts_v2"></a> [log\_alerts\_v2](#output\_log\_alerts\_v2) | Map of created v2 log alert resources. |
| <a name="output_metric_alerts"></a> [metric\_alerts](#output\_metric\_alerts) | Map of created metric alert resources. |
| <a name="output_resource_health_alerts"></a> [resource\_health\_alerts](#output\_resource\_health\_alerts) | Map of created Resource Health activity log alerts, keyed by subscription scope. |
| <a name="output_service_health_alerts"></a> [service\_health\_alerts](#output\_service\_health\_alerts) | Map of created Service Health activity log alerts, keyed by subscription scope. |
| <a name="output_warnings"></a> [warnings](#output\_warnings) | Operational warnings. Check this output for potential configuration issues. |
<!-- END_TF_DOCS -->
