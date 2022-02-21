locals {
  query_frontend_replicas        = 1
  querier_component_name         = "querier"
  query_frontend_component_name  = "query-frontend"
  query_scheduler_component_name = "query-scheduler"
  distributor_component_name     = "distributor"
  ingester_component_name        = "ingester"
  querier_hostname               = "${var.service_name}-${local.querier_component_name}.${var.namespace_name}.svc.cluster.local"
  query_frontend_hostname        = "${var.service_name}-${local.query_frontend_component_name}-headless.${var.namespace_name}.svc.cluster.local"
  #  query_scheduler_hostname       = "${var.service_name}-${local.query_scheduler_component_name}.${var.namespace_name}.svc.cluster.local"
  remote_write_url = "http://${var.service_name}-${local.distributor_component_name}.${var.namespace_name}.svc.cluster.local:${var.service_port}/loki/api/v1/push"
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
  #  query_scheduler_hostname    = local.query_scheduler_hostname
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
  system_name          = var.service_name
  component_name       = local.ingester_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_checksum      = module.loki_config.config_checksum
  config_map_name      = module.loki_config.config_map_name
  config_mount_path    = module.loki_config.config_mount_path
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 4
  replicas             = 1
}

module "querier" {
  source               = "../common/stateful"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.querier_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_checksum      = module.loki_config.config_checksum
  config_map_name      = module.loki_config.config_map_name
  config_mount_path    = module.loki_config.config_mount_path
  storage_mount_path   = module.loki_config.storage_mount_path
  storage_volume_size  = 2
  replicas             = 1
}

module "distributor" {
  source               = "../common/stateless"
  namespace_name       = var.namespace_name
  system_name          = var.service_name
  component_name       = local.distributor_component_name
  service_account_name = module.service_account.name
  container_image      = var.container_image
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_checksum      = module.loki_config.config_checksum
  config_map_name      = module.loki_config.config_map_name
  config_mount_path    = module.loki_config.config_mount_path
  storage_mount_path   = module.loki_config.storage_mount_path
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
  service_http_port    = module.loki_config.service_http_port
  service_grpc_port    = module.loki_config.service_grpc_port
  etcd_host            = module.loki_config.etcd_host
  config_filename      = module.loki_config.config_filename
  config_checksum      = module.loki_config.config_checksum
  config_map_name      = module.loki_config.config_map_name
  config_mount_path    = module.loki_config.config_mount_path
  storage_mount_path   = module.loki_config.storage_mount_path
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
#  service_http_port    = module.loki_config.service_http_port
#  service_grpc_port    = module.loki_config.service_grpc_port
#  etcd_host            = module.loki_config.etcd_host
#  config_filename      = module.loki_config.config_filename
#  config_checksum = module.loki_config.config_checksum
#  config_map_name      = module.loki_config.config_map_name
#  config_mount_path    = module.loki_config.config_mount_path
#  storage_mount_path   = module.loki_config.storage_mount_path
#  storage_volume_size  = 1
#  replicas             = 1
#}