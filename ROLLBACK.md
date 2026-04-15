# Rollback Strategies

## Quick disable — all alerts

Set `apply_default_rules = false` and clear custom alerts:
```hcl
apply_default_rules  = false
custom_log_alerts    = {}
custom_metric_alerts = {}
action_groups        = {}
```
Run `tofu apply`. All alert resources destroyed, action groups removed. External AGs untouched.

## Disable single default rule

```hcl
default_alert_rules_configuration = {
  default_firewall_health = { disable_rule = true }
}
```

## Disable single custom alert

Remove its key from `custom_log_alerts` or `custom_metric_alerts`, run apply.

## Wrong alert_profile deployed

Change `alert_profile` to the correct one (or `null`). Previous profile's alerts destroyed, new ones created. Stateless — no drift risk.

## LAW not reachable / 403 on log alerts

1. All log alerts depend on `log_analytics_workspace_id`. If LAW deleted or access revoked, alerts stay in Azure but stop evaluating.
2. To remove orphaned alerts: set `alert_profile = null`, `custom_log_alerts = {}`, apply.
3. To fix access: restore LAW or update `log_analytics_workspace_id` to new LAW, apply.

## Identity/role assignment failure

If managed identity alerts fail with 403:
1. Check `azurerm_role_assignment.log_alert` — verify principal_id and scope.
2. Role propagation can take up to 10 minutes in Azure AD.
3. As workaround: disable identity on the alert via `default_alert_rules_configuration` override:
   ```hcl
   update_management_failed_update_window = { disable_rule = true }
   ```

## Complete rollback — remove module

```hcl
# Remove the module block entirely, then:
tofu apply
```
All module-created resources destroyed. External action groups and LAW untouched.

## State corruption

```bash
# List resources in state
tofu state list | grep "module.monitoring"

# Remove specific resource from state (resource stays in Azure)
tofu state rm 'module.monitoring.azurerm_monitor_metric_alert.this["default_firewall_health"]'

# Import back if needed
tofu import 'module.monitoring.azurerm_monitor_metric_alert.this["default_firewall_health"]' /subscriptions/.../metricAlerts/...
```

## Version rollback

Pin module source to previous version:
```hcl
source = "git::https://github.com/glueckkanja/terraform-azurerm-gkvm-ptn-monitoringsuite.git?ref=v0.1.0"
```
Run `tofu init -upgrade && tofu apply`.
