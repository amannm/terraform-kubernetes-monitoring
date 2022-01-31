variable "namespace_name" {
  type = string
}
variable "resource_name" {
  type    = string
  default = "grafana-agent"
}
variable "container_image" {
  type    = string
  default = "grafana/agent:v0.22.0"
}
variable "container_port" {
  type    = number
  default = 80
}
variable "metrics_remote_write_url" {
  type = string
}