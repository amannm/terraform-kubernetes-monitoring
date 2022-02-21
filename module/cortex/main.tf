locals {
  query_frontend_replicas        = 1
  prometheus_api_path            = "/prometheus"
  querier_component_name         = "querier"
  query_scheduler_component_name = "query-scheduler"
  query_frontend_component_name  = "query-frontend"
  distributor_component_name     = "distributor"
  ingester_component_name        = "ingester"
  compactor_component_name       = "compactor"
  store_gateway_component_name   = "store-gateway"
  querier_hostname               = "${var.service_name}-${local.querier_component_name}.${var.namespace_name}.svc.cluster.local"
  query_frontend_hostname        = "${var.service_name}-${local.query_frontend_component_name}.${var.namespace_name}.svc.cluster.local"
  #  query_scheduler_hostname       = "${var.service_name}-${local.query_scheduler_component_name}.${var.namespace_name}.svc.cluster.local"
  distributor_hostname = "${var.service_name}-${local.distributor_component_name}.${var.namespace_name}.svc.cluster.local"
  remote_write_url     = "http://${local.distributor_hostname}:${var.service_port}/api/v1/push"
}

module "cortex_config" {
  source                  = "./module/config"
  namespace_name          = var.namespace_name
  service_name            = var.service_name
  etcd_host               = var.etcd_host
  http_port               = var.service_port
  grpc_port               = 9095
  querier_hostname        = local.querier_hostname
  query_frontend_hostname = local.query_frontend_hostname
  #  query_scheduler_hostname    = local.query_scheduler_hostname
  prometheus_api_path         = local.prometheus_api_path
  max_query_frontend_replicas = local.query_frontend_replicas
}

module "service_account" {
  source         = "../common/service-account"
  namespace_name = var.namespace_name
  service_name   = var.service_name
}

module "ingester" {
  source               = "../common/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.ingester_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "compactor" {
  source               = "../common/stateful"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.compactor_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "store-gateway" {
  source               = "../common/stateful"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.store_gateway_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "querier" {
  source               = "../common/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.querier_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "distributor" {
  source               = "../common/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.distributor_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = 1
}

module "query_frontend" {
  source               = "../common/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.query_frontend_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.cortex_config.service_http_port
  service_grpc_port    = module.cortex_config.service_grpc_port
  etcd_host            = module.cortex_config.etcd_host
  config_filename      = module.cortex_config.config_filename
  config_map_name      = module.cortex_config.config_map_name
  config_mount_path    = module.cortex_config.config_mount_path
  storage_mount_path   = module.cortex_config.storage_mount_path
  storage_volume_size  = 1
  replicas             = local.query_frontend_replicas
}

#module "query_scheduler" {
#  source               = "../common/stateless"
#  namespace_name       = var.namespace_name
#  system_name          = var.service_name
#  component_name       = local.query_scheduler_component_name
#  service_account_name = module.service_account.name
#  container_image      = var.container_image
#  service_http_port    = module.cortex_config.service_http_port
#  service_grpc_port    = module.cortex_config.service_grpc_port
#  etcd_host            = module.cortex_config.etcd_host
#  config_filename      = module.cortex_config.config_filename
#  config_map_name      = module.cortex_config.config_map_name
#  config_mount_path    = module.cortex_config.config_mount_path
#  storage_mount_path   = module.cortex_config.storage_mount_path
#  storage_volume_size  = 1
#  replicas             = 1
#}