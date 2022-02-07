locals {
  querier_component_name        = "querier"
  query_frontend_component_name = "query-frontend"
  distributor_component_name    = "distributor"
  ingester_component_name       = "ingester"
  querier_hostname              = "${var.service_name}-${local.querier_component_name}.${var.namespace_name}.svc.cluster.local"
  query_frontend_hostname       = "${var.service_name}-${local.query_frontend_component_name}.${var.namespace_name}.svc.cluster.local"
  distributor_host              = "${var.service_name}-${local.distributor_component_name}.${var.namespace_name}.svc.cluster.local:${var.service_port}"
}

module "loki_config" {
  source                  = "./module/config"
  namespace_name          = var.namespace_name
  service_name            = var.service_name
  etcd_host               = var.etcd_host
  http_port               = var.service_port
  grpc_port               = 9095
  querier_hostname        = local.querier_hostname
  query_frontend_hostname = local.query_frontend_hostname
}

module "service_account" {
  source         = "../common/service-account"
  namespace_name = var.namespace_name
  service_name   = var.service_name
}

module "ingester" {
  source               = "./module/stateful"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.ingester_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_map_name      = module.loki_config.config_map_name
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 4
  replicas             = 1
}

module "querier" {
  source               = "./module/stateful"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.querier_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_map_name      = module.loki_config.config_map_name
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 2
  replicas             = 1
}

module "distributor" {
  source               = "./module/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.distributor_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  service_grpclb_port  = 9096
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_map_name      = module.loki_config.config_map_name
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "query_frontend" {
  source               = "./module/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.query_frontend_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  service_grpclb_port  = 9096
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_map_name      = module.loki_config.config_map_name
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}