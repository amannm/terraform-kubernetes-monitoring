variable "namespace_name" {
  type = string
}
variable "resource_name" {
  type = string
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