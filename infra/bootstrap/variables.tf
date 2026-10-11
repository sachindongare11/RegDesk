variable "project" {
  description = "Short project name, used in every resource name."
  type        = string
  default     = "regdesk"
}

variable "location" {
  description = "Azure region for the state storage account."
  type        = string
  default     = "centralindia"
}

variable "tags" {
  description = "Tags applied to every resource this config creates."
  type        = map(string)
  default = {
    project     = "regdesk"
    environment = "bootstrap"
  }
}
