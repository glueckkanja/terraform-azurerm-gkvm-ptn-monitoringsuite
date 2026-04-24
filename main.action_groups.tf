resource "azurerm_monitor_action_group" "this" {
  for_each = var.action_groups

  name                = local.action_group_names[each.key]
  resource_group_name = var.resource_group_name
  short_name          = each.value.short_name
  enabled             = each.value.enabled
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = each.value.email_receivers

    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = email_receiver.value.use_common_alert_schema
    }
  }

  # webhook_receiver.service_uri may be substituted from var.pagerduty_config
  # when the caller sets pagerduty_key. Because pagerduty_config is marked
  # sensitive, OpenTofu emits a notice that a sensitive value is used in a
  # non-sensitive attribute. This is expected behaviour; no action is required.
  dynamic "webhook_receiver" {
    for_each = local.resolved_webhook_receivers[each.key]

    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = webhook_receiver.value.use_common_alert_schema
    }
  }

  dynamic "sms_receiver" {
    for_each = each.value.sms_receivers

    content {
      name         = sms_receiver.value.name
      country_code = sms_receiver.value.country_code
      phone_number = sms_receiver.value.phone_number
    }
  }

  dynamic "azure_app_push_receiver" {
    for_each = each.value.azure_app_push_receivers

    content {
      name          = azure_app_push_receiver.value.name
      email_address = azure_app_push_receiver.value.email_address
    }
  }

  dynamic "arm_role_receiver" {
    for_each = each.value.arm_role_receivers

    content {
      name                    = arm_role_receiver.value.name
      role_id                 = arm_role_receiver.value.role_id
      use_common_alert_schema = arm_role_receiver.value.use_common_alert_schema
    }
  }

  dynamic "logic_app_receiver" {
    for_each = each.value.logic_app_receivers

    content {
      name                    = logic_app_receiver.value.name
      resource_id             = logic_app_receiver.value.resource_id
      callback_url            = logic_app_receiver.value.callback_url
      use_common_alert_schema = logic_app_receiver.value.use_common_alert_schema
    }
  }

  dynamic "azure_function_receiver" {
    for_each = each.value.azure_function_receivers

    content {
      name                     = azure_function_receiver.value.name
      function_app_resource_id = azure_function_receiver.value.function_app_resource_id
      function_name            = azure_function_receiver.value.function_name
      http_trigger_url         = azure_function_receiver.value.http_trigger_url
      use_common_alert_schema  = azure_function_receiver.value.use_common_alert_schema
    }
  }

  lifecycle {
    ignore_changes = [tags]

    # nonsensitive() is applied to keys() of the sensitive pagerduty_config
    # map. The keys themselves are not secret (only the webhook URLs are);
    # without this, OpenTofu would classify the entire error message as
    # sensitive and suppress it, hiding useful diagnostics from the operator.
    precondition {
      condition = alltrue([
        for wh_key, wh in each.value.webhook_receivers :
        wh.pagerduty_key == null || contains(nonsensitive(keys(var.pagerduty_config)), wh.pagerduty_key)
      ])
      error_message = format(
        "action_groups[%q].webhook_receivers contains a pagerduty_key (%s) not found in var.pagerduty_config. Add the matching entry to pagerduty_config or correct the key name.",
        each.key,
        join(", ", [
          for wh_key, wh in each.value.webhook_receivers :
          format("%q (receiver %q)", wh.pagerduty_key, wh_key)
          if wh.pagerduty_key != null && !contains(nonsensitive(keys(var.pagerduty_config)), wh.pagerduty_key)
        ])
      )
    }
  }
}
