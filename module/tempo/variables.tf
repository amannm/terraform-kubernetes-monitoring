variable "cluster_domain" {
  type = string
}
variable "namespace_name" {
  type = string
}
variable "service_name" {
  type = string
}
variable "stateless_node_labels" {
  type = map(set(string))
}
variable "storage_volume_size" {
  type = number
}
variable "container_image" {
  type = string
}
variable "service_port" {
  type = number
}
variable "service_account" {
  type = object({
    name        = string
    annotations = map(string)
  })
}
variable "etcd_host" {
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