variable "namespace_name" {
  type = string
}
variable "app_name" {
  type = string
}
variable "component_name" {
  type = string
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "agentctl_container_image" {
  type = string
}
variable "agent_host" {
  type = string
}
variable "remote_write_url" {
  type = string
}
variable "refresh_rate" {
  type = number
}
variable "etcd_host" {
  type = string
}
variable "partition_by_labels" {
  type = map(set(string))
}