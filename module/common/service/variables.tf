variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
  type = string
}
variable "service_name" {
  type = string
}
variable "non_headless_only" {
  type    = bool
  default = false
}
variable "headless_only" {
  type    = bool
  default = false
}
variable "wait_for_readiness" {
  type    = bool
  default = true
}
variable "ports" {
  type = map(object({
    port        = number
    target_port = number
  }))
}
