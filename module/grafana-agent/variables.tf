variable "namespace_name" {
  type = string
}
variable "resource_name" {
  type    = string
  default = "grafana-agent"
}
variable "agent_container_image" {
  type    = string
  default = "grafana/agent:v0.22.0"
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
  type    = string
  default = "grafana/agentctl:v0.22.0"
}
variable "etcd_host" {
  type = string
}
variable "logs_remote_write_url" {
  type    = string
  default = null
}