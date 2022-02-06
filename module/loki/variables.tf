variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "service_port" {
  type = number
}
variable "storage_volume_size" {
  type = number
}
variable "container_image" {
  type = string
}
variable "container_http_port" {
  type    = number
  default = 3100
}
variable "container_grpc_port" {
  type    = number
  default = 9095
}
variable "etcd_host" {
  type = string
}