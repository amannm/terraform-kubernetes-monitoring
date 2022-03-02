variable "namespace_name" {
  type = string
}
variable "resource_name" {
  type = string
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "agent_container_image" {
  type = string
}
variable "agent_container_port" {
  type    = number
  default = 80
}
variable "metrics_remote_write_url" {
  type    = string
  default = null
}
variable "agentctl_container_image" {
  type = string
}
variable "etcd_host" {
  type = string
}
variable "logs_remote_write_url" {
  type    = string
  default = null
}
variable "partition_by_labels" {
  type    = map(set(string))
  default = {}
}