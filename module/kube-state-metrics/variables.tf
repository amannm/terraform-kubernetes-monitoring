variable "namespace_name" {
  type = string
}
variable "service_name" {
  type    = string
  default = "kube-state-metrics"
}
variable "service_port" {
  type    = number
  default = 8080
}
variable "preemptible_node_label_name" {
  type = string
}
variable "preemptible_node_label_value" {
  type = string
}
variable "container_image" {
  type    = string
  default = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "container_metrics_port" {
  type    = number
  default = 8081
}