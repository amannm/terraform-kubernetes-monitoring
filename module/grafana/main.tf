locals {
  health_check_path = "/api/health"

  config_volume_name       = "config"
  config_volume_mount_path = "/etc/grafana"

  storage_volume_name       = "storage"
  storage_volume_mount_path = "/var/lib/grafana"
}

resource "kubernetes_service" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    type             = "ClusterIP"
    session_affinity = "None"
    port {
      protocol    = "TCP"
      port        = var.service_port
      target_port = var.container_port
    }
    selector = {
      component = var.service_name
    }
  }
}

// TODO: break out all config
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    "grafana.ini" = <<-EOT

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
}

resource "kubernetes_persistent_volume_claim" "persistent_volume_claim" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    resources {
      requests = {
        storage = "${var.storage_volume_size}Gi"
      }
    }
    access_modes = [
      "ReadWriteOnce"
    ]
  }
}

resource "kubernetes_deployment" "deployment" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    replicas = "1"
    strategy {
      type = "RollingUpdate"
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
        security_context {
          run_as_user         = "472"
          run_as_group        = "472"
          fs_group            = "472"
          supplemental_groups = [0]
        }
        volume {
          name = local.config_volume_name
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        volume {
          name = local.storage_volume_name
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.persistent_volume_claim.metadata[0].name
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          resources {
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "250Mi"
            }
          }
          port {
            protocol       = "TCP"
            container_port = var.container_port
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
              port   = var.container_port
              path   = local.health_check_path
            }
            timeout_seconds       = 2
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            failure_threshold     = 3
          }
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
        }
      }
    }
  }
}