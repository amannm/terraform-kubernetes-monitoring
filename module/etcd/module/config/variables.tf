variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "client_port" {
  type = number
}
variable "peer_port" {
  type = number
}
variable "config_filename" {
  type = string
}
variable "data_volume_mount_path" {
  type = string
}
variable "otlp_receiver_endpoint" {
  type = string
}