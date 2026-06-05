variable "naming_configuration" {
  type        = any
  description = "Standesamt naming configuration object. Obtained from the standesamt_config data source."
}

variable "convention" {
  type        = string
  description = "Naming convention. Use 'passthrough' to skip convention and pass resource name through directly."
}

variable "environment" {
  type        = string
  description = "Environment name used in resource naming (e.g., prod, dev, test)."
}

variable "name_prefixes" {
  type        = list(string)
  default     = []
  description = "Name prefixes for resource naming."
}

variable "name_suffixes" {
  type        = list(string)
  default     = []
  description = "Name suffixes for resource naming."
}

variable "name_precedence" {
  type        = list(string)
  default     = []
  description = "Name precedence rules for resource naming."
}

variable "hash_length" {
  type        = number
  default     = 0
  description = "Hash length for resource naming."
}

variable "naming_configuration_custom" {
  type        = any
  default     = null
  description = "Optional standesamt naming configuration produced by a standesamt_config data source whose provider loads a custom schema (custom_url). Supplies naming for resource types absent from the azure/caf library (e.g. azurerm_monitor_alert_processing_rule_suppression). Its schema entries are merged under var.naming_configuration; the normal naming schema wins on conflict."
}
