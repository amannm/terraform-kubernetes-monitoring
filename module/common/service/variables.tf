variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
  type    = string
  default = "cluster.local"
}
variable "service_name" {
  type = string
}
variable "non_headless_only" {
  type    = bool
  default = false
  #  validation {
  #    condition = var.non_headless_only == true && var.headless_only == true
  #    error_message = "\"disable_headless\" and \"headless_only\" cannot both be set to true."
  #  }
}
variable "headless_only" {
  type    = bool
  default = false
  #  validation {
  #    condition = var.non_headless_only == true && var.headless_only == true
  #    error_message = "\"disable_headless\" and \"headless_only\" cannot both be set to true."
  #  }
}
variable "ports" {
  type = map(object({
    port        = number
    target_port = number
  }))
}
