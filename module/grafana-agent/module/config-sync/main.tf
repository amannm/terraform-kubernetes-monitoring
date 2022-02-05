locals {
  config_filename          = "agent.yaml"
  config_volume_name       = "config"
  config_volume_mount_path = "/etc/configs"
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = var.config_yaml
  }
}
resource "kubernetes_cron_job" "config_update_job" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
  spec {
    schedule                      = "*/5 * * * *"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    job_template {
      metadata {
        name = var.resource_name
      }
      spec {
        ttl_seconds_after_finished = "120"
        template {
          metadata {
            name = var.resource_name
          }
          spec {
            restart_policy          = "OnFailure"
            active_deadline_seconds = 600
            volume {
              name = local.config_volume_name
              config_map {
                name = kubernetes_config_map.config_map.metadata[0].name
              }
            }
            container {
              name              = var.resource_name
              image             = var.container_image
              image_pull_policy = "IfNotPresent"
              args = [
                "config-sync",
                local.config_volume_mount_path,
                "--addr",
                "http://${var.agent_api_host}",
              ]
              volume_mount {
                name       = local.config_volume_name
                mount_path = local.config_volume_mount_path
              }
            }
          }
        }
      }
    }
  }
}
