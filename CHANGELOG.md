# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.7.1] - 2026-08-19

### Changed

- **`default_alert_rules_configuration` is now explicitly typed** as `map(object({...}))` with
  `optional()` on every field, replacing `type = any`. OpenTofu converts each attribute
  individually, so a value keeps the type it was written as regardless of how the consumer's
  variable plumbing unified the map. Both `true` and `"true"` are accepted for `disable_rule`,
  and both `3` and `"3"` for `severity`. No input that previously worked stops working:
  unrecognised field names are still dropped silently, null fields fall back to the rule's
  default, and `action_group_ids = []` still means notify nobody while `null` still falls back
  to severity routing.
- **Stateful default log alerts, now documented** — effective since 0.7.0:
  `auto_mitigation_enabled` defaults to `true` for default log alerts — one fired alert per
  episode, auto-resolved when the condition clears. Custom log alerts and metric alerts already
  defaulted to stateful. Opt out per rule via
  `default_alert_rules_configuration.<rule>.auto_mitigation_enabled = false`.

### Fixed

- **`disable_rule` ignored when overrides arrive stringified** — with the variable typed `any`,
  a map whose entries have different shapes (one rule overriding only `name`, another only
  `disable_rule`) was unified by OpenTofu to `map(map(string))`, so `disable_rule = true`
  reached the module as the string `"true"`. The filter compared it with `!= true`, which is
  always true for a string, and the rule was never removed — the alert stayed deployed with no
  indication anything had been ignored. Fixed by the explicit variable type above.
- **Explicit nulls in `default_alert_rules_configuration` override rule values** — typed
  consumer objects with `optional(..., null)` fields send explicit nulls for unset override
  fields; these leaked through `lookup()` and replaced rule values (a null `severity` even
  breaks alert naming at plan time). Null override fields now fall back to the rule's default.
- **Auto-mitigation vs. mute guard** — a default log alert that sets
  `mute_actions_after_alert_duration` keeps `auto_mitigation_enabled = false`; azurerm forbids
  combining the two on `azurerm_monitor_scheduled_query_rules_alert_v2`.
- **Auto-mitigation vs. low-frequency guard** — rules evaluated less often than every 12 hours
  keep `auto_mitigation_enabled = false`; the Azure API rejects stateful rules above that
  frequency with a 400 (`Stateful rules can not run in a frequency greater than 12 hours`).

## [0.7.0] - 2026-08-17

### Added

- **Namespace scoping for kubernetes_workload alerts** — new `namespace` variable scopes the
  `kubernetes_workload` profile's log alerts (pod CrashLoopBackOff, OOMKilled, unavailable
  deployments, pending pods) to a single Kubernetes namespace instead of cluster-wide, via a
  generated `${namespace_filter}` KQL predicate. Only valid with `alert_profile =
  "kubernetes_workload"` — rejected at plan time on any other profile. The namespace is also
  folded into the alert name and description so multiple per-namespace module instances can
  coexist in one resource group.

### Fixed

- **Severity routing with null `action_group_ids`** — replaced conditional ternary expressions
  with `coalesce()` in metric alert and log alert (v1/v2) action routing to prevent a plan-time
  `Inconsistent conditional result types` error when default-rule loading propagates
  `action_group_ids = null` into merged alert maps. `null` still falls back to severity-based
  routing, `[]` still means explicit no-notification, and an explicit list still overrides
  per-alert — only the plan-time crash is fixed.

## [0.6.1] - 2026-08-03

### Fixed

- **Health alerts now respect severity routing** — Service Health and Resource Health activity
  log alerts previously notified every configured action group, ignoring severity. Azure stamps
  activity log alerts with a fixed `Sev4` in the common alert schema, so `health_alert_action_group_ids`
  now includes only action groups whose `severities` contain `4` (both external and
  module-created groups).

### Changed

- **Breaking change** — action groups without `4` in `severities` no longer receive health alert
  notifications. Add `4` to any group that should retain them — typically ticket or email groups,
  not on-call paging groups.

## [0.6.0] - 2026-07-27

### Added

- **`data_lake_deletion_exclusions`** — a list of `{paths, object_ids}` rules for the
  `data_lake` profile's deletion alerts, letting customers scope out known-expected ADLS
  deletions (e.g. a Databricks staging pipeline's create/merge/drop churn) without blinding the
  alert to real data loss. A deletion is excluded only if its path matches a rule's `paths`
  **and** (no `object_ids` given, or the caller's `RequesterObjectId` is one of them). The
  matching KQL predicate is generated at plan time and exposed via a new
  `${data_lake_deletion_exclusion_predicate}` placeholder in the `query_template` substitution
  chain. Empty exclusions (the default) resolve to a no-op — zero behavior change for existing
  customers.

## [0.5.0] - 2026-06-30

### Added

- **PagerDuty-friendly alert descriptions** — every alert description (metric, log v1/v2,
  service health, resource health) is now prefixed with `[<name_prefixes[0]>]`, so PagerDuty
  incident titles are customer-identifiable under the one-service-per-solution model. An empty
  `name_prefixes` produces no change.

## [0.4.0] - 2026-06-05

### Added

- **Alert processing rule suppressions** — new `alert_processing_rule_suppressions` variable
  creates `azurerm_monitor_alert_processing_rule_suppression` resources with all 11 condition
  dimensions as dynamic blocks, daily/weekly/monthly schedule recurrence, and scope inheritance
  from `var.scopes`. Empty `condition = {}` is rejected at plan time. New
  `alert_processing_rule_suppressions` output; the existing `alert_count` output gains an
  `alert_processing_rule_suppressions` key and an updated `total`.

## [0.3.0] - 2026-05-11

### Added

- **User-assigned managed identity (UAMI) support for log alerts** — `custom_log_alerts.identity`
  gained an `identity_ids` field, and a new `default_log_alert_identity_ids` variable injects a
  UAMI into default-profile log alerts that declare no identity in their YAML. Required for
  queries that reach outside the bound Log Analytics Workspace (e.g. `adx()` against a Fabric
  Eventhouse, `workspace()` across subscriptions, `arg()`). Automatic Reader role assignments
  remain SystemAssigned-only, since UserAssigned identities expose no `principal_id` on the
  alert resource.
- **Fabric/ADX query template variables** — `adx_cluster_uri`, `fabric_capacity_id`, and
  `fabric_workspace_id` (renamed from `eventhouse_uri`) are substituted into query templates via
  `${adx_cluster_uri}`, `${fabric_capacity_id}`, and `${fabric_workspace_id}` placeholders, for
  alert profiles that reference a specific ADX/Eventhouse cluster, capacity, or workspace.

### Fixed

- **Incorrect standesamt resource type for log alert v2** — resources were named using
  `azurerm_monitor_scheduled_query_rules_alert_v2` as the standesamt resource type; both v1
  and v2 map to the same Azure resource type `azurerm_monitor_scheduled_query_rules_alert`.
- **Apply-time plan failure from unknown template variables** — `adx_cluster_uri`,
  `fabric_capacity_id`, and `fabric_workspace_id` may be unknown at plan time (e.g. derived
  from a UAMI data source), which caused `merged_log_alerts_v2`'s `for_each` key computation
  to fail when those values were substituted at the map-key level. Substitutions are now
  deferred to the resource `query` attribute (a value path, not a key path).

## [0.2.0] - 2026-04-24

### Added

- **Health alerts** — new `health_alerts` variable deploys `azurerm_monitor_activity_log_alert`
  resources for Azure Service Health and Resource Health, one per unique subscription extracted
  from `var.scopes`. Activity log alerts notify every configured action group; severity routing
  does not apply. Supersedes the standalone `af/monitoring/health_alert` module.
- **Optional alerting** — alerting is now fully optional. Setting `alert_profile = null`,
  `apply_default_rules = false`, and passing no `custom_*_alerts` lets the module be deployed
  solely for action groups and/or health alerts.
- **PagerDuty integration** — new `pagerduty_config` variable accepts a catalog of
  `{name, webhook}` entries. Webhook receivers can reference an entry via `pagerduty_key`;
  the module substitutes the receiver name (`"PagerDuty <name>"`) and `service_uri` at plan
  time. The variable is marked `sensitive` so webhook URLs never appear in plan diffs.
- `service_health_alerts` and `resource_health_alerts` outputs.
- `health_alerts.service_health.statuses` and `health_alerts.resource_health.statuses` —
  optional activity-log event status filter (`Active`, `In Progress`, `Resolved`, `Updated`).
  Lets callers restrict notifications to, for example, only newly active incidents.

### Changed

- `scopes` regex validation relaxed to accept subscription-only IDs (`/subscriptions/<guid>`)
  in addition to full resource IDs. Enables health-alert-only deployments.
- `action_groups[].webhook_receivers[]` gained optional `pagerduty_key`. The `service_uri`
  validation is now null-safe and enforces that each webhook receiver sets either `pagerduty_key`
  or an `https://` `service_uri`.
- A `lifecycle.precondition` on `azurerm_monitor_action_group` fails the plan when a
  `pagerduty_key` references a missing entry in `pagerduty_config`.

### Migration — replacing the old `af/monitoring/health_alert` module

Remove the old module block from your root configuration. OpenTofu will plan the destruction
of the old activity log alerts (and any resource group managed by it) and the creation of
the new alerts under this module. Activity log alerts operate on the Azure event stream and
hold no stored state — recreation causes no notification gap and no data loss.

## [0.1.1] - 2026-04-22

### Added

- `LICENSE` file.

### Removed

- Usage examples section from `README.md`.

## [0.1.0] - 2026-04-22

First public release of `terraform-azurerm-gkvm-ptn-monitoringsuite` — a GKVM-pattern
OpenTofu module for Azure Monitor alerting on any scope-based Azure resource.

The module manages metric alerts, log-based scheduled query alerts (v1 and v2),
action groups, and the role assignments required for managed-identity log alerts.
Alert profiles and default rule libraries are served by the companion
[`glueckkanja/gkvm`](https://registry.terraform.io/providers/glueckkanja/gkvm) provider.

### Added

#### Alert resources

- **`azurerm_monitor_metric_alert`** — metric-based alerts with multi-criteria support,
  dynamic thresholds, and per-alert action group routing by severity.
- **`azurerm_monitor_scheduled_query_rules_alert_v2`** — KQL log alerts (v2) with optional
  managed identity, dimensions, metric measure columns, and muted actions.
- **`azurerm_monitor_scheduled_query_rules_alert`** — KQL log alerts (v1) for metric-trigger
  patterns that the v2 API cannot express (result count + metric threshold in one rule).

#### Action groups

- **`azurerm_monitor_action_group`** — module-managed action groups with email, webhook,
  Logic App, Azure Function, ARM role, Automation Runbook, ITSM, and Event Hub receivers.
- **Hybrid routing** — external action groups (passed in as resource IDs) and module-managed
  action groups are merged into a unified routing table. Both types are filtered by severity
  level (0 – 4) per alert.

#### Identity and RBAC

- **`azurerm_role_assignment`** — automatic role assignments for log alerts that use a
  system-assigned managed identity. Default log alert rules receive `Reader` on the monitored
  scope and on the Log Analytics Workspace. Custom log alert rules receive the assignments
  declared in their `identity.role_assignments` block.

#### Default alert library (via `gkvm` provider)

- **`defaults_override`** variable — accepts `data.gkvm_monitoring_profiles.this.profiles`
  from the [`glueckkanja/gkvm`](https://registry.terraform.io/providers/glueckkanja/gkvm)
  provider. Each value is a JSON string containing `metric_alerts` and `log_alerts` maps.
  See [gkvm provider integration](#gkvm-provider-integration) below.
- **`alert_profile`** — selects which profile from the library to activate.
- **Opt-out model** (all profiles except `appzone`) — all default rules in a profile are
  active unless individually disabled via `default_alert_rules_configuration[key].disable_rule`.
- **Opt-in model** (`appzone` profile) — only rules explicitly listed in
  `default_alert_rules_configuration` are created. Designed for heterogeneous application
  workloads where not every alert applies.
- **Per-rule overrides** — `name`, `severity`, `threshold`, `window_size`, `frequency`, and
  `auto_mitigate` can be overridden per rule without disabling it.

#### Custom alerts

- **`custom_metric_alerts`** — fully custom metric alerts merged on top of (and taking
  precedence over) default metric alerts.
- **`custom_log_alerts`** — fully custom log alerts. The placeholder `%%SCOPE%%` in KQL
  queries is substituted with the first entry in `var.scopes` at plan time.

#### Naming

- All resources are named via the
  [`glueckkanja/standesamt`](https://registry.terraform.io/providers/glueckkanja/standesamt)
  provider function `provider::standesamt::name()`. Names enforce Azure length limits and
  abbreviation conventions automatically.
- Severity is appended as a suffix (`sev0` … `sev4`) so alert names are self-describing
  in the Azure portal.

#### CI/CD

- GitHub Actions pipeline with six jobs: `format`, `validate`, `test`, `security`
  (Checkov + SARIF upload), `tflint`, `docs`.
- Native `tofu test` unit tests with mock providers — no Azure credentials required in CI.
- `release.yml` — validates the module and publishes a GitHub Release on every semver tag.
- Dependabot — weekly grouped updates for GitHub Actions and provider versions.
- `terraform-docs` auto-regenerated on PR branches — contributors do not need the tool
  installed locally.

#### gkvm provider integration

This module has an **optional but recommended** dependency on the
[`glueckkanja/gkvm`](https://registry.terraform.io/providers/glueckkanja/gkvm) provider.

```
terraform-provider-gkvm
  └── data "gkvm_monitoring_profiles" "this" {}
        └── reads YAML profiles from github.com/glueckkanja/gkvm-monitoring-defaults
              └── returns map of profile_name → JSON string
                    └── passed to this module via var.defaults_override
```

**Without the provider** the module still works, but only with fully custom alerts
(`custom_metric_alerts`, `custom_log_alerts`). No built-in default profiles are available.

**With the provider** you get access to the full alert profile library — `firewall`,
`appzone`, `express_route`, `avd`, `virtual_machine`, and more — maintained centrally in
[`glueckkanja/gkvm-monitoring-defaults`](https://github.com/glueckkanja/gkvm-monitoring-defaults)
and versioned independently of this module.

##### Minimal wiring

```hcl
terraform {
  required_providers {
    gkvm = {
      source  = "glueckkanja/gkvm"
      version = ">= 0.1.0, < 1.0"
    }
  }
}

provider "gkvm" {
  github_repo = "glueckkanja/gkvm-monitoring-defaults"
  github_ref  = "main"
  # Token resolved automatically from GH_TOKEN / GITHUB_TOKEN / gh CLI
}

data "gkvm_monitoring_profiles" "this" {}

module "monitoring" {
  source = "glueckkanja/gkvm-ptn-monitoringsuite/azurerm"

  defaults_override = data.gkvm_monitoring_profiles.this.profiles
  alert_profile     = "firewall"
  # ...
}
```

##### Pinning a specific profile snapshot

The `github_ref` attribute in the provider block accepts any branch, tag, or commit SHA.
Pin to a tag to get reproducible, immutable alert definitions:

```hcl
provider "gkvm" {
  github_repo = "glueckkanja/gkvm-monitoring-defaults"
  github_ref  = "v1.2.0"
}
```
