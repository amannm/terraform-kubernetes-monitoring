variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
  type = string
}
variable "service_name" {
  type = string
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "storage_volume_size" {
  type = number
}
variable "container_image" {
  type = string
}
variable "service_port" {
  type = number
}
variable "etcd_host" {
  type = string
}