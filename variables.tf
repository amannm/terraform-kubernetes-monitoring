variable "namespace_name" {
  type    = string
  default = "monitoring"
}
variable "kube_state_metrics_port" {
  type    = number
  default = 8080
}
variable "grafana_port" {
  type    = number
  default = 3000
}
variable "cortex_port" {
  type    = number
  default = 9090
}
variable "loki_port" {
  type    = number
  default = 3100
}
variable "preemptible_node_label_name" {
  type    = string
  default = null
}
variable "preemptible_node_label_value" {
  type    = any
  default = null
}