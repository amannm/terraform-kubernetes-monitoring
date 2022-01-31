variable "namespace_name" {
  type = string
}
variable "service_name" {
  type    = string
  default = "prometheus-server"
}
variable "service_port" {
  type = number
}
variable "storage_volume_size" {
  type    = number
  default = 4
}
variable "storage_retention_days" {
  type    = number
  default = 1
}
variable "server_container_image" {
  type    = string
  default = "quay.io/prometheus/prometheus:v2.31.1"
}
variable "server_container_port" {
  type    = number
  default = 9090
}