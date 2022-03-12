variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "http_port" {
  type = number
}
variable "grpc_port" {
  type = number
}
variable "gossip_port" {
  type = number
}
variable "config_filename" {
  type    = string
  default = "config.yaml"
}
variable "config_path" {
  type    = string
  default = "/etc/loki/config"
}
variable "storage_path" {
  type    = string
  default = "/var/loki"
}
variable "query_frontend_hostname" {
  type = string
}
#variable "query_scheduler_hostname" {
#  type = string
#}
variable "querier_hostname" {
  type = string
}
variable "gossip_hostnames" {
  type = set(string)
}
variable "max_query_frontend_replicas" {
  type = number
}
variable "storage_config" {
  type = object({
    local = object({
      volume_size = number
    })
    gcp = object({
      bucket_name = string
    })
  })
}