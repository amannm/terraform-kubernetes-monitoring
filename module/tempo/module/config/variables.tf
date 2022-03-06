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
variable "otlp_grpc_port" {
  type = number
}
variable "config_filename" {
  type = string
}
variable "config_path" {
  type = string
}
variable "storage_path" {
  type = string
}
variable "query_frontend_hostname" {
  type = string
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