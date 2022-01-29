variable "namespace_name" {
  type = string
}
variable "service_name" {
  type    = string
  default = "prometheus-node-exporter"
}
variable "service_port" {
  type    = number
  default = 9100
}
variable "container_image" {
  type    = string
  default = "quay.io/prometheus/node-exporter:v1.3.0"
}
variable "container_port" {
  type    = number
  default = 9100
}