locals {
  query_frontend_replicas = 2
  remote_write_url        = "http://${var.service_name}-distributor.${var.namespace_name}.svc.cluster.local:${var.service_port}/loki/api/v1/push"
  partition_by_labels = {
    component = values(local.service_names),
  }
  pod_lifecycle = {
    min_readiness_time = 30
    max_readiness_time = 90
    max_cleanup_time   = 30
  }
  pod_probes = {
    port                   = module.loki_config.service_http_port
    readiness_path         = "/ready"
    liveness_path          = "/ready"
    readiness_polling_rate = 5
    liveness_polling_rate  = 5
  }
  ports = {
    http = {
      port        = module.loki_config.service_http_port
      target_port = module.loki_config.service_http_port
    }
    grpc = {
      port        = module.loki_config.service_grpc_port
      target_port = module.loki_config.service_grpc_port
    }
  }
  config_volumes = {
    config = {
      mount_path      = module.loki_config.config_mount_path
      config_map_name = module.loki_config.config_map_name
      config_checksum = module.loki_config.config_checksum
    }
  }
  storage_volumes = {
    storage = {
      mount_path = module.loki_config.storage_mount_path
      size       = 1
    }
  }
  components = ["ingester", "distributor", "querier", "query-frontend"]
  component_args = {
    for c in local.components : c => [
      "-config.file=${module.loki_config.config_mount_path}/${module.loki_config.config_filename}",
      "-target=${c}",
    ]
  }
  service_names = { for c in local.components : c => "${var.service_name}-${c}" }
}

module "loki_config" {
  source                      = "./module/config"
  namespace_name              = var.namespace_name
  service_name                = var.service_name
  etcd_host                   = var.etcd_host
  http_port                   = var.service_port
  grpc_port                   = 9095
  querier_hostname            = "${var.service_name}-querier.${var.namespace_name}.svc.cluster.local"
  query_frontend_hostname     = "${var.service_name}-query-frontend-headless.${var.namespace_name}.svc.cluster.local"
  max_query_frontend_replicas = local.query_frontend_replicas
}

module "service_account" {
  source         = "../common/service-account"
  namespace_name = var.namespace_name
  service_name   = var.service_name
}

module "ingester" {
  source               = "../common/stateful"
  namespace_name       = var.namespace_name
  service_name         = local.service_names["ingester"]
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  args                 = local.component_args["ingester"]
  pod_resources = {
    cpu_min    = 75
    memory_min = 50
    memory_max = 150
  }
  ports                 = local.ports
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  persistent_volumes    = local.storage_volumes
  stateless_node_labels = var.stateless_node_labels
}

module "querier" {
  source       = "../common/stateless"
  service_name = local.service_names["querier"]
  args         = local.component_args["querier"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 40
    memory_max = 70
  }
  namespace_name        = var.namespace_name
  service_account_name  = module.service_account.name
  replicas              = 1
  container_image       = var.container_image
  ports                 = local.ports
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  stateless_node_labels = var.stateless_node_labels
}

module "distributor" {
  source       = "../common/stateless"
  service_name = local.service_names["distributor"]
  args         = local.component_args["distributor"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 20
    memory_max = 70
  }
  namespace_name        = var.namespace_name
  service_account_name  = module.service_account.name
  replicas              = 1
  container_image       = var.container_image
  ports                 = local.ports
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  stateless_node_labels = var.stateless_node_labels
}

module "query_frontend" {
  source       = "../common/stateless"
  service_name = local.service_names["query-frontend"]
  args         = local.component_args["query-frontend"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 16
    memory_max = 40
  }
  namespace_name        = var.namespace_name
  service_account_name  = module.service_account.name
  replicas              = 1
  container_image       = var.container_image
  ports                 = local.ports
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  stateless_node_labels = var.stateless_node_labels
}