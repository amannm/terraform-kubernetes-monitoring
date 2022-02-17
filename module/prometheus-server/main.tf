locals {
  config_filename = "prometheus.yml"

  config_volume_name       = "config"
  config_volume_mount_path = "/etc/config"

  storage_volume_name       = "storage"
  storage_volume_mount_path = "/data"

  ports = {
    http = {
      port        = var.service_port
      target_port = var.server_container_port
    }
  }
}

module "service" {
  source            = "../common/service"
  namespace_name    = var.namespace_name
  service_name      = var.service_name
  non_headless_only = true
  ports             = local.ports
}

module "persistent_volume_claim" {
  source         = "../common/persistent-volume-claim"
  namespace_name = var.namespace_name
  service_name   = var.service_name
  size           = var.storage_volume_size
}

module "prometheus_config" {
  source          = "./module/config"
  namespace_name  = var.namespace_name
  config_map_name = var.service_name
  config_filename = local.config_filename
}

resource "kubernetes_deployment" "deployment" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        component = var.service_name
      }
    }
    template {
      metadata {
        labels = {
          component = var.service_name
        }
      }
      spec {
        termination_grace_period_seconds = 30
        dns_policy                       = "ClusterFirst"
        security_context {
          fs_group        = "65534"
          run_as_group    = "65534"
          run_as_non_root = true
          run_as_user     = "65534"
        }
        volume {
          name = local.config_volume_name
          config_map {
            name = module.prometheus_config.config_map_name
          }
        }
        volume {
          name = local.storage_volume_name
          persistent_volume_claim {
            claim_name = module.persistent_volume_claim.name
          }
        }
        container {
          name              = var.service_name
          image             = var.server_container_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--config.file=${local.config_volume_mount_path}/${local.config_filename}",
            "--storage.tsdb.path=${local.storage_volume_mount_path}",
            "--storage.tsdb.retention=${var.storage_retention_days}d",
            "--web.enable-lifecycle",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--web.enable-remote-write-receiver",
          ]
          port {
            protocol       = "TCP"
            container_port = var.server_container_port
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
            limits = {
              memory = "500Mi"
            }
          }
          volume_mount {
            name       = local.config_volume_name
            mount_path = local.config_volume_mount_path
          }
          volume_mount {
            name       = local.storage_volume_name
            mount_path = local.storage_volume_mount_path
          }
          readiness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.server_container_port
              path   = "/-/ready"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 10
            success_threshold     = 1
          }
          liveness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.server_container_port
              path   = "/-/healthy"
            }
            initial_delay_seconds = 330
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 1
            success_threshold     = 1
          }
        }
      }
    }
  }
}