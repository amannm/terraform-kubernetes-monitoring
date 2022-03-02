variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
  type = string
}
variable "app_name" {
  type = string
}
variable "component_name" {
  type    = string
  default = null
}
variable "service_account_name" {
  type = string
}
variable "replicas" {
  type = number
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "container_image" {
  type = string
}
variable "config_volumes" {
  type = map(object({
    mount_path      = string
    config_map_name = string
    config_checksum = string
  }))
  default = {}
}
variable "ephemeral_volumes" {
  type = map(object({
    mount_path = string
    size       = number
  }))
  default = {}
}
variable "command" {
  type    = list(string)
  default = null
}
variable "args" {
  type    = list(string)
  default = null
}
variable "ports" {
  type = map(object({
    port        = optional(number)
    target_port = number
  }))
}
variable "pod_resources" {
  type = object({
    cpu_min    = number
    memory_min = number
    memory_max = number
  })
}
variable "pod_lifecycle" {
  type = object({
    min_readiness_time    = number
    max_readiness_time    = number
    max_cleanup_time      = number
    shutdown_hook_path    = optional(string)
    shutdown_exec_command = optional(list(string))
  })
}
variable "pod_probes" {
  type = object({
    port                   = number
    readiness_path         = string
    liveness_path          = string
    readiness_polling_rate = number
    liveness_polling_rate  = number
  })
}
variable "pod_security_context" {
  type = object({
    uid                       = number
    added_capabilities        = optional(list(string))
    read_only_root_filesystem = optional(bool)
    supplemental_groups       = optional(list(string))
  })
  default = null
}
variable "pod_name_env_var" {
  type    = string
  default = null
}
variable "wait_for_readiness" {
  type    = bool
  default = true
}