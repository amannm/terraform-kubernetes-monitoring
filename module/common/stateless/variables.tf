variable "namespace_name" {
  type = string
}
variable "system_name" {
  type = string
}
variable "preemptible_node_label_name" {
  type = string
}
variable "preemptible_node_label_value" {
  type = string
}
variable "storage_volume_size" {
  type = number
}
variable "container_image" {
  type = string
}
variable "service_http_port" {
  type = number
}
variable "service_grpc_port" {
  type = number
}
variable "etcd_host" {
  type = string
}
variable "config_map_name" {
  type = string
}
variable "config_filename" {
  type = string
}
variable "config_checksum" {
  type = string
}
variable "replicas" {
  type = number
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
    min_readiness_time = number
    max_readiness_time = number
    max_cleanup_time   = number
    shutdown_hook_path = optional(string)
  })
}
variable "service_account_name" {
  type = string
}
variable "storage_mount_path" {
  type = string
}
variable "config_mount_path" {
  type = string
}
variable "component_name" {
  type = string
}