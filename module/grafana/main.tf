locals {
  health_check_path             = "/api/health"
  config_path                   = "/etc/grafana"
  provisioning_config_directory = "${local.config_path}/provisioning"
  datasources_config_directory  = "${local.provisioning_config_directory}/datasources"
  storage_volume_mount_path     = "/var/lib/grafana"
  service_host                  = "${module.grafana.hostname}:${var.service_port}"
}

module "config" {
  source                        = "./module/config"
  config_filename               = "grafana.ini"
  container_port                = var.container_port
  namespace_name                = var.namespace_name
  config_map_name               = var.service_name
  provisioning_config_directory = local.provisioning_config_directory
}

module "datasources_config" {
  source          = "./module/datasources-config"
  config_filename = "datasources.yaml"
  namespace_name  = var.namespace_name
  config_map_name = "${var.service_name}-datasources"
  prometheus_url  = var.prometheus_url
  loki_url        = var.loki_url
  tempo_url       = var.tempo_url
}

module "service_account" {
  source               = "../common/service-account"
  namespace_name       = var.namespace_name
  service_account_name = var.service_name
}

module "grafana" {
  source               = "../common/stateful"
  cluster_domain       = var.cluster_domain
  namespace_name       = var.namespace_name
  app_name             = var.service_name
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  pod_resources = {
    cpu_min    = 75
    memory_min = 55
    memory_max = 70
  }
  pod_lifecycle = {
    min_readiness_time = 10
    max_readiness_time = 90
    max_cleanup_time   = 30
  }
  pod_probes = {
    port                   = var.container_port
    readiness_path         = local.health_check_path
    liveness_path          = local.health_check_path
    readiness_polling_rate = 5
    liveness_polling_rate  = 5
  }
  pod_security_context = {
    uid                 = 472
    supplemental_groups = [0]
  }
  config_volumes = {
    config = {
      mount_path      = local.config_path
      config_map_name = module.config.config_map_name
      config_checksum = module.config.config_checksum
    }
    datasources = {
      mount_path      = local.datasources_config_directory
      config_map_name = module.datasources_config.config_map_name
      config_checksum = module.datasources_config.config_checksum
    }
  }
  persistent_volumes = {
    data = {
      mount_path = local.storage_volume_mount_path
      size       = 1
    }
  }
  stateless_node_labels = var.stateless_node_labels
  ports = {
    http = {
      port        = var.service_port
      target_port = var.container_port
    }
  }
}
// TODO: conditional liveness probe on stateful
/*
          liveness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.container_port
              path   = local.health_check_path
            }
            timeout_seconds       = 30
            initial_delay_seconds = 60
            period_seconds        = 10
            success_threshold     = 1
            failure_threshold     = 10
          }
*/