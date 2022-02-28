locals {
  health_check_path         = "/api/health"
  config_volume_mount_path  = "/etc/grafana"
  storage_volume_mount_path = "/var/lib/grafana"
  service_host              = "${module.grafana.hostname}:${var.service_port}"
  config_file_content       = <<-EOT
  [paths]
  data = ${local.storage_volume_mount_path}
  temp_data_lifetime = 24h
  logs = ${local.storage_volume_mount_path}/log
  plugins = ${local.storage_volume_mount_path}/plugins
  provisioning = ${local.config_volume_mount_path}/provisioning

  [server]
  protocol = http
  http_port = ${var.container_port}

  [analytics]
  reporting_enabled = false
  check_for_updates = true

  [snapshots]
  external_enabled = false

  [log]
  mode = console
  level = info

  [metrics]
  enabled = true

  EOT

}

// TODO: break out all config
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    "grafana.ini" = local.config_file_content
  }
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
}

module "grafana" {
  source               = "../common/stateful"
  namespace_name       = var.namespace_name
  service_name         = var.service_name
  service_account_name = kubernetes_service_account.service_account.metadata[0].name
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
      mount_path      = local.config_volume_mount_path
      config_map_name = kubernetes_config_map.config_map.metadata[0].name
      config_checksum = sha256(local.config_file_content)
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