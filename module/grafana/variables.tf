variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
  type = string
}
variable "service_name" {
  type = string
}
variable "service_port" {
  type = number
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "container_image" {
  type = string
}
variable "container_port" {
  type = number
}
variable "storage_volume_size" {
  type = number
}