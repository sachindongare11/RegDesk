variable "name" {
  description = "ACR name. Must be globally unique, 5-50 alphanumeric characters, no hyphens."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  description = "Basic/Standard/Premium. Basic has no private endpoint support and a smaller image size quota -- fine for a dev registry with 3 small service images."
  type        = string
  default     = "Basic"
}

variable "tags" {
  type    = map(string)
  default = {}
}
