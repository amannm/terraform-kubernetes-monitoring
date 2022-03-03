variable "namespace_name" {
  type    = string
  default = "monitoring"
}
variable "cluster_domain" {
  type    = string
  default = "cluster.local"
}
variable "kube_state_metrics_port" {
  type    = number
  default = 8080
}
variable "grafana_port" {
  type    = number
  default = 3000
}
variable "etcd_port" {
  type    = number
  default = 2379
}
variable "grafana_agent_port" {
  type    = number
  default = 80
}
variable "jaeger_grpc_receiver_port" {
  type    = number
  default = 14250
}
variable "cortex_port" {
  type    = number
  default = 9090
}
variable "loki_port" {
  type    = number
  default = 3100
}
variable "stateless_node_labels" {
  type    = map(set(string))
  default = {}
}