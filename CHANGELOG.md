# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [0.1.0] — 2026-04-22

### Overview

First public release of `terraform-azurerm-gkvm-ptn-monitoringsuite` — a GKVM-pattern
OpenTofu module for Azure Monitor alerting on any scope-based Azure resource.

The module manages metric alerts, log-based scheduled query alerts (v1 and v2),
action groups, and the role assignments required for managed-identity log alerts.
Alert profiles and default rule libraries are served by the companion
[`glueckkanja/gkvm`](https://registry.terraform.io/providers/glueckkanja/gkvm) provider.

---

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
  See [Provider relationship](#provider-relationship) below.
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

---

### Provider relationship

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

#### Minimal wiring

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

#### Pinning a specific profile snapshot

The `github_ref` attribute in the provider block accepts any branch, tag, or commit SHA.
Pin to a tag to get reproducible, immutable alert definitions:

```hcl
provider "gkvm" {
  github_repo = "glueckkanja/gkvm-monitoring-defaults"
  github_ref  = "v1.2.0"
}
```

---

[Unreleased]: https://github.com/glueckkanja/terraform-azurerm-gkvm-ptn-monitoringsuite/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/glueckkanja/terraform-azurerm-gkvm-ptn-monitoringsuite/releases/tag/v0.1.0
