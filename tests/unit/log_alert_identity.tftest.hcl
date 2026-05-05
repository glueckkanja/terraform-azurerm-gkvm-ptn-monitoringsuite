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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/azureFirewalls/fw-test"]
  alert_profile       = null
  apply_default_rules = false
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = {}

  log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  log_analytics_workspace_location = "westeurope"

  action_group_routing = [
    {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Insights/actionGroups/ag-test"
      severities      = [0, 1, 2, 3, 4]
    }
  ]
}

run "user_assigned_identity_wired_into_alert" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_log_alerts = {
      fabric_query = {
        name     = "fabric-query-alert"
        severity = 2
        query    = "AzureActivity | limit 10"
        identity = {
          enabled      = true
          type         = "UserAssigned"
          identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-fabric"]
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this) == 1
    error_message = "Expected exactly one v2 log alert."
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["fabric_query"].identity[0].type == "UserAssigned"
    error_message = "Alert identity type should be UserAssigned."
  }

  assert {
    condition = contains(
      azurerm_monitor_scheduled_query_rules_alert_v2.this["fabric_query"].identity[0].identity_ids,
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-fabric"
    )
    error_message = "Alert identity_ids should contain the specified UAMI resource ID."
  }
}

run "no_identity_block_creates_no_identity" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_log_alerts = {
      plain_alert = {
        name     = "plain-alert"
        severity = 3
        query    = "AzureActivity | limit 10"
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_scheduled_query_rules_alert_v2.this["plain_alert"].identity) == 0
    error_message = "Alert without identity block should have no identity."
  }
}

run "system_assigned_identity_unchanged" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    custom_log_alerts = {
      sys_alert = {
        name     = "system-identity-alert"
        severity = 2
        query    = "AzureActivity | limit 10"
        identity = {
          enabled = true
          type    = "SystemAssigned"
        }
      }
    }
  }

  assert {
    condition     = azurerm_monitor_scheduled_query_rules_alert_v2.this["sys_alert"].identity[0].type == "SystemAssigned"
    error_message = "SystemAssigned identity type should be unchanged."
  }
}
