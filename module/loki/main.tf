locals {
  query_frontend_replicas = 1
  remote_write_url        = "http://${var.service_name}-distributor.${var.namespace_name}.svc.${var.cluster_domain}:${var.service_port}/loki/api/v1/push"
  loki_url                = "http://${var.service_name}-query-frontend.${var.namespace_name}.svc.${var.cluster_domain}:${var.service_port}"
  pod_lifecycle = {
    min_readiness_time = 30
    max_readiness_time = 90
    max_cleanup_time   = 30
  }
  pod_probes = {
    port                   = local.ports.http.port
    readiness_path         = "/ready"
    liveness_path          = "/ready"
    readiness_polling_rate = 5
    liveness_polling_rate  = 5
  }
  ports = {
    http = {
      port        = var.service_port
      target_port = var.service_port
    }
    grpc = {
      port        = 9095
      target_port = 9095
    }
  }
  gossip_port = {
    port        = 7946
    target_port = 7946
  }
  ports_with_gossip = merge(local.ports, {
    gossip = local.gossip_port
  })
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
  security_context = {
    uid                       = 10001
    read_only_root_filesystem = true
  }
  components = ["distributor", "ingester", "compactor", "querier", "query-frontend"]
  component_args = {
    for c in local.components : c => [
      "-config.file=${module.loki_config.config_mount_path}/${module.loki_config.config_filename}",
      "-target=${c}",
    ]
  }
}

module "loki_config" {
  source                  = "./module/config"
  namespace_name          = var.namespace_name
  service_name            = var.service_name
  http_port               = local.ports.http.port
  grpc_port               = local.ports.grpc.port
  querier_hostname        = "${var.service_name}-querier.${var.namespace_name}.svc.${var.cluster_domain}"
  query_frontend_hostname = "${var.service_name}-query-frontend-headless.${var.namespace_name}.svc.${var.cluster_domain}"
  #  index_gateway_hostname = "${var.service_name}-index-gateway-headless.${var.namespace_name}.svc.${var.cluster_domain}"
  gossip_port = local.gossip_port.port
  gossip_hostnames = [
    "${var.service_name}-distributor-headless.${var.namespace_name}.svc.${var.cluster_domain}",
    "${var.service_name}-ingester-headless.${var.namespace_name}.svc.${var.cluster_domain}",
    "${var.service_name}-compactor-headless.${var.namespace_name}.svc.${var.cluster_domain}",
  ]
  max_query_frontend_replicas = local.query_frontend_replicas
  storage_config              = var.storage_config
}

module "service_account" {
  source               = "../common/service-account"
  namespace_name       = var.namespace_name
  service_account_name = var.service_account.name
  annotations          = var.service_account.annotations
}

module "distributor" {
  source         = "../common/stateless"
  cluster_domain = var.cluster_domain
  app_name       = var.service_name
  component_name = "distributor"
  args           = local.component_args["distributor"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 20
    memory_max = 100
  }
  namespace_name        = var.namespace_name
  service_account_name  = module.service_account.name
  replicas              = 1
  container_image       = var.container_image
  ports                 = local.ports_with_gossip
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  pod_security_context  = local.security_context
  stateless_node_labels = var.stateless_node_labels
}

module "ingester" {
  source               = "../common/stateful"
  cluster_domain       = var.cluster_domain
  namespace_name       = var.namespace_name
  app_name             = var.service_name
  component_name       = "ingester"
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  args                 = local.component_args["ingester"]
  pod_resources = {
    cpu_min    = 75
    memory_min = 70
    memory_max = 300
  }
  ports                 = local.ports_with_gossip
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  persistent_volumes    = local.storage_volumes
  pod_security_context  = local.security_context
  stateless_node_labels = var.stateless_node_labels
}

module "compactor" {
  source         = "../common/stateless"
  cluster_domain = var.cluster_domain
  app_name       = var.service_name
  component_name = "compactor"
  args           = local.component_args["compactor"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 26
    memory_max = 100
  }
  namespace_name        = var.namespace_name
  service_account_name  = module.service_account.name
  replicas              = 1
  container_image       = var.container_image
  ports                 = local.ports_with_gossip
  pod_lifecycle         = local.pod_lifecycle
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  pod_security_context  = local.security_context
  stateless_node_labels = var.stateless_node_labels
}

module "querier" {
  source         = "../common/stateless"
  cluster_domain = var.cluster_domain
  app_name       = var.service_name
  component_name = "querier"
  args           = local.component_args["querier"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 40
    memory_max = 1000
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
  pod_security_context  = local.security_context
  stateless_node_labels = var.stateless_node_labels
}

module "query_frontend" {
  source         = "../common/stateless"
  cluster_domain = var.cluster_domain
  app_name       = var.service_name
  component_name = "query-frontend"
  args           = local.component_args["query-frontend"]
  pod_resources = {
    cpu_min    = 50
    memory_min = 16
    memory_max = 1000
  }
  namespace_name       = var.namespace_name
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  ports                = local.ports
  pod_lifecycle = {
    min_readiness_time = 5
    max_readiness_time = 10
    max_cleanup_time   = 5
  }
  pod_probes            = local.pod_probes
  config_volumes        = local.config_volumes
  ephemeral_volumes     = local.storage_volumes
  pod_security_context  = local.security_context
  stateless_node_labels = var.stateless_node_labels
}