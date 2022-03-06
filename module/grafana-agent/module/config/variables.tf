variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "config_filename" {
  type = string
}
variable "agent_container_port" {
  type = number
}
variable "node_exporter_config" {
  type = object({
    host_root_volume_mount_path = string
    host_sys_volume_mount_path  = string
    host_proc_volume_mount_path = string
  })
  default = null
}
variable "metrics_config" {
  type = object({
    remote_write_url         = string
    agent_host               = string
    etcd_host                = string
    agentctl_container_image = string
    partition_by_labels      = map(set(string))
  })
  default = null
}
variable "logs_config" {
  type = object({
    remote_write_url            = string
    positions_volume_mount_path = string
  })
  default = null
}
variable "traces_config" {
  type = object({
    jaeger_receiver_port  = number
    zipkin_receiver_port  = number
    remote_write_endpoint = string
  })
  default = null
}