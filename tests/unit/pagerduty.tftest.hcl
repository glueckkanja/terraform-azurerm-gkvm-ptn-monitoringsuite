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
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"]
  alert_profile       = null
  apply_default_rules = false
  location            = "westeurope"
  resource_group_name = "rg-monitoring-test"
  environment         = "test"
  convention          = "passthrough"
  tags                = {}
}

run "pagerduty_key_resolves_webhook" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    pagerduty_config = {
      ops = {
        name    = "ops-team"
        webhook = "https://events.pagerduty.com/integration/abcdef/enqueue"
      }
    }

    action_groups = {
      pager = {
        short_name = "pager"
        severities = [0, 1]
        webhook_receivers = {
          primary = {
            pagerduty_key = "ops"
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 1
    error_message = "Action group with pagerduty_key must plan successfully."
  }
}

run "direct_service_uri_still_accepted" {
  command = plan

  variables {
    naming_configuration = run.setup.naming_configuration

    action_groups = {
      hook = {
        short_name = "hook"
        severities = [0]
        webhook_receivers = {
          primary = {
            name        = "primary"
            service_uri = "https://example.com/hook"
          }
        }
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this) == 1
    error_message = "Direct https service_uri webhooks must still plan successfully."
  }
}
