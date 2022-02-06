variable "namespace_name" {
  type    = string
  default = "monitoring"
}
variable "kube_state_metrics_port" {
  type    = number
  default = 8080
}
variable "prometheus_server_port" {
  type    = number
  default = 9090
}
variable "prometheus_node_exporter_port" {
  type    = number
  default = 9100
}
variable "grafana_port" {
  type    = number
  default = 3000
}
variable "loki_port" {
  type    = number
  default = 3100
}