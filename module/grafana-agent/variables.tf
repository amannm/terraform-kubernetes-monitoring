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
variable "agent_container_image" {
  type = string
}
variable "service_port" {
  type = number
}
variable "jaeger_receiver_port" {
  type = number
}
variable "zipkin_receiver_port" {
  type = number
}
variable "metrics_remote_write_url" {
  type    = string
  default = null
}
variable "logs_remote_write_url" {
  type    = string
  default = null
}
variable "traces_remote_write_url" {
  type    = string
  default = null
}
variable "agentctl_container_image" {
  type = string
}
variable "etcd_host" {
  type = string
}
variable "partition_by_labels" {
  type    = map(set(string))
  default = {}
}