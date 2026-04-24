variable "location" {
  type    = string
  default = "westeurope"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "resource_group_name" {
  type    = string
  default = "rg-monitoring-prod-we"
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace"
}

variable "log_analytics_workspace_location" {
  type        = string
  description = "Location of the Log Analytics Workspace"
  default     = "westeurope"
}

variable "firewall_resource_id" {
  type        = string
  description = "Resource ID of the Azure Firewall to monitor"
}

variable "app_scope" {
  type        = string
  description = "Full resource ID of the application scope (e.g., /subscriptions/00000000-.../resourceGroups/rg-app)"
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app"
}

variable "pagerduty_config" {
  type = map(object({
    name    = string
    webhook = string
  }))
  default     = {}
  sensitive   = true
  description = "PagerDuty webhook catalog. Keys referenced by action_groups[].webhook_receivers[].pagerduty_key."
}
