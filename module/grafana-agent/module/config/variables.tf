variable "namespace_name" {
  type = string
}
variable "server_container_port" {
  type = number
}
variable "metrics_remote_write_url" {
  type = string
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