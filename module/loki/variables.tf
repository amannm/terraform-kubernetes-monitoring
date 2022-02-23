variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "preemptible_node_label_name" {
  type = string
}
variable "preemptible_node_label_value" {
  type = any
}
variable "storage_volume_size" {
  type = number
}
variable "container_image" {
  type = string
}
variable "service_port" {
  type    = number
  default = 3100
}
variable "etcd_host" {
  type = string
}