variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "http_port" {
  type = number
}
variable "etcd_host" {
  type = string
}
variable "grpc_port" {
  type = number
}
variable "config_filename" {
  type    = string
  default = "config.yaml"
}
variable "config_path" {
  type    = string
  default = "/etc/cortex/config"
}
variable "storage_path" {
  type    = string
  default = "/var/cortex"
}
variable "query_frontend_hostname" {
  type = string
}
variable "prometheus_api_path" {
  type    = string
  default = "/prometheus"
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
      bucket_name                 = string
      service_account_annotations = map(string)
    })
  })
}