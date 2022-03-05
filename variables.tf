variable "namespace_name" {
  type    = string
  default = "observability"
}
variable "cluster_domain" {
  type    = string
  default = "cluster.local"
}
variable "kube_state_metrics_port" {
  type    = number
  default = 8080
}
variable "grafana_port" {
  type    = number
  default = 3000
}
variable "etcd_port" {
  type    = number
  default = 2379
}
variable "grafana_agent_port" {
  type    = number
  default = 80
}
variable "jaeger_receiver_port" {
  type    = number
  default = 14268
}
variable "cortex_port" {
  type    = number
  default = 9090
}
variable "tempo_port" {
  type    = number
  default = 9090
}
variable "loki_port" {
  type    = number
  default = 3100
}
variable "stateless_node_labels" {
  type    = map(set(string))
  default = {}
}

// TODO: add aws and azure support
variable "cortex_storage_config" {
  type = object({
    local = object({
      volume_size = number
    })
    gcp = object({
      bucket_name = string
    })
  })
  default = {
    local = {
      volume_size = 1
    }
    gcp = null
  }
  validation {
    condition     = length([for k, v in var.cortex_storage_config : k if v != null]) == 1
    error_message = "Exactly 1 storage type must be defined."
  }
}

// TODO: add aws and azure support
variable "loki_storage_config" {
  type = object({
    local = object({
      volume_size = number
    })
    gcp = object({
      bucket_name = string
    })
  })
  default = {
    local = {
      volume_size = 1
    }
    gcp = null
  }
  validation {
    condition     = length([for k, v in var.loki_storage_config : k if v != null]) == 1
    error_message = "Exactly 1 storage type must be defined."
  }
}

// TODO: add aws and azure support
variable "tempo_storage_config" {
  type = object({
    local = object({
      volume_size = number
    })
    gcp = object({
      bucket_name = string
    })
  })
  default = {
    local = {
      volume_size = 1
    }
    gcp = null
  }
  validation {
    condition     = length([for k, v in var.tempo_storage_config : k if v != null]) == 1
    error_message = "Only 1 storage type can be defined at a time."
  }
}

variable "cortex_service_account" {
  type = object({
    name        = string
    annotations = map(string)
  })
  default = {
    name        = "cortex"
    annotations = {}
  }
}
variable "loki_service_account" {
  type = object({
    name        = string
    annotations = map(string)
  })
  default = {
    name        = "loki"
    annotations = {}
  }
}
variable "tempo_service_account" {
  type = object({
    name        = string
    annotations = map(string)
  })
  default = {
    name        = "tempo"
    annotations = {}
  }
}