variable "namespace_name" {
  type = string
}
variable "service_name" {
  type    = string
  default = "grafana"
}
variable "service_port" {
  type = number
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "container_image" {
  type    = string
  default = "grafana/grafana:8.3.4"
}
variable "container_port" {
  type    = number
  default = 3000
}
variable "storage_volume_size" {
  type    = number
  default = 2
}