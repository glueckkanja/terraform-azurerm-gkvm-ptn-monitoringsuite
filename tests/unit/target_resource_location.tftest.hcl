mock_provider "azurerm" {}
mock_provider "standesamt" {}
mock_provider "modtm" {}
mock_provider "random" {}

run "setup" {
  module {
    source = "./tests/unit/setup"
  }

  providers = {
    azurerm = azurerm
    modtm   = modtm
    random  = random
  }
}

variables {
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/zone.test"]
  alert_profile       = "private_dns_zone"
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = { environment = "test" }

  defaults_override = {
    private_dns_zone = "{\"metric_alerts\":{\"default_record_sets\":{\"name\":\"pdns-record-sets\",\"description\":\"Record set capacity\",\"severity\":2,\"window_size\":\"PT15M\",\"frequency\":\"PT5M\",\"metric_namespace\":\"Microsoft.Network/privateDnsZones\",\"target_resource_location\":\"global\",\"alert_criterias\":[{\"metric_name\":\"RecordSetCapacityUtilization\",\"operator\":\"GreaterThan\",\"aggregation\":\"Maximum\",\"threshold\":90}]}},\"log_alerts\":{}}"
  }

  custom_metric_alerts = {
    custom_global = {
      name                     = "custom-global"
      severity                 = 2
      metric_namespace         = "Microsoft.Network/privateDnsZones"
      target_resource_location = "global"
      alert_criterias = [{
        metric_name = "QueryVolume"
        operator    = "GreaterThan"
        aggregation = "Total"
        threshold   = 1000
      }]
    }
    custom_regional = {
      name             = "custom-regional"
      severity         = 3
      metric_namespace = "Microsoft.Network/privateDnsZones"
      alert_criterias = [{
        metric_name = "QueryVolume"
        operator    = "GreaterThan"
        aggregation = "Total"
        threshold   = 5000
      }]
    }
  }
}

# A profile rule carrying target_resource_location overrides var.location;
# rules and custom alerts without it keep the var.location fallback.
run "target_resource_location_override" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["default_record_sets"].target_resource_location == "global"
    error_message = "Profile-served target_resource_location must override var.location."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["custom_global"].target_resource_location == "global"
    error_message = "Custom metric alert target_resource_location must be honoured."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["custom_regional"].target_resource_location == "westeurope"
    error_message = "Without target_resource_location the alert must fall back to var.location."
  }
}

# The dimensions override replaces a default rule's criteria dimensions.
run "dimensions_override" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    default_alert_rules_configuration = {
      default_record_sets = {
        dimensions = [{
          name   = "RecordType"
          values = ["A", "AAAA"]
        }]
      }
    }
  }

  assert {
    condition     = [for d in tolist(azurerm_monitor_metric_alert.this["default_record_sets"].criteria)[0].dimension : d.name] == ["RecordType"]
    error_message = "The dimensions override must reach the metric alert criteria."
  }
}
