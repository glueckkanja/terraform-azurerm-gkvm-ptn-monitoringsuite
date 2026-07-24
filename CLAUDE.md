# CLAUDE.md — terraform-azurerm-gkvm-ptn-monitoringsuite

## What is this module?

A GKVM-pattern (glueckkanja Verified Module) OpenTofu module for Azure Monitor alerting.
Follows AVM (Azure Verified Modules) conventions. Focused on alerting only — no Data Collection Rules.

## Architecture decisions

- **Generalized scoping**: Uses `scopes` (list of resource IDs) + `alert_profile` instead of `resource_id` + `resource_type`
- **Hybrid action groups**: Supports both external (passed-in) and module-created action groups
- **Severity routing**: Action groups are filtered by severity level — core feature, do not change
- **v1 + v2 log alerts**: v2 preferred; v1 kept for metric trigger patterns that v2 cannot express
- **Default alert library**: YAML-based, one file per profile in `defaults/*.yaml`, auto-loaded by `locals.defaults.tf`
- **No resource group creation**: RG is always external
- **No LAW creation**: Log Analytics Workspace always external
- **DCR is separate**: Data Collection Rules will be a future separate GKVM module

## Naming

Uses standesamt provider v2.x with provider-defined functions (`standesamt::name()`).
Requires `standesamt_config` data source for configuration object.

## Provider versions

All providers pinned to exact versions. Update regularly.

## File conventions

- `main.*.tf` — resource definitions by domain
- `defaults/*.yaml` — default alert definitions, one YAML file per profile (auto-discovered)
- `locals.defaults.tf` — YAML loader, config override logic, profile maps
- `locals.tf` — core merge logic, naming, action group unification
- `variables.tf` — core variables
- `variables.naming.tf` — standesamt naming interface
- `terraform.tf` — provider requirements

## Adding a new alert profile

1. Create `defaults/<profile_name>.yaml` with `metric_alerts` and `log_alerts` keys
2. Use `query_template` with `${primary_scope}`, `${remote_ip}`, `${bandwidth}`, `${data_lake_deletion_exclusion_predicate}` for variable substitution
3. No HCL changes needed — `fileset()` auto-discovers new YAML files

## Testing

Uses `tofu test` (native OpenTofu test framework). Tests in `tests/unit/`.

## Commands

- `tofu init` — initialize providers
- `tofu validate` — validate configuration
- `tofu test` — run unit tests
- `tofu fmt -recursive` — format all files
