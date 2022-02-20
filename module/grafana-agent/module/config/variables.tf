variable "namespace_name" {
  type = string
}
variable "config_map_name" {
  type = string
}
variable "config_filename" {
  type = string
}
variable "agent_container_port" {
  type = number
}
variable "host_root_volume_mount_path" {
  type = string
}
variable "host_sys_volume_mount_path" {
  type = string
}
variable "host_proc_volume_mount_path" {
  type = string
}
variable "etcd_endpoint" {
  type = string
}
variable "positions_volume_mount_path" {
  type = string
}
variable "loki_remote_write_url" {
  type = string
}