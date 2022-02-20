variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
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
    metrics_remote_write_url = string
    agent_host               = string
    etcd_host                = string
    agentctl_container_image = string
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