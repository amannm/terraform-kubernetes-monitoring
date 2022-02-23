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
  type = string
}
variable "container_image" {
  type = string
}
variable "cluster_size" {
  type = number
}
variable "storage_volume_size" {
  type = number
}