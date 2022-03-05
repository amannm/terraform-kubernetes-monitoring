variable "namespace_name" {
  type = string
}
variable "cluster_domain" {
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
variable "service_account_name" {
  type = string
}
variable "etcd_host" {
  type = string
}
variable "storage_config" {
  type = object({
    local = optional(object({
      volume_size = number
    }))
    gcp = optional(object({
      bucket_name                 = string
      service_account_annotations = map(string)
    }))
  })
  validation {
    condition     = length([for k, v in var.storage_config : k if v != null]) == 1
    error_message = "Exactly 1 storage type must be defined."
  }
}