variable "namespace_name" {
  type = string
}
variable "system_name" {
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
variable "service_grpclb_port" {
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
variable "replicas" {
  type = number
}
variable "service_account_name" {
  type = string
}
variable "storage_mount_path" {
  type = string
}
variable "config_mount_path" {
  type    = string
  default = "/etc/cortex/config"
}
variable "component_name" {
  type = string
}