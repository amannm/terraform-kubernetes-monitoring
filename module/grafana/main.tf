locals {
  component_name = "grafana"
}

resource "kubernetes_service" "service" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
    annotations = {
      "prometheus.io/scrape" = true
    }
  }
  spec {
    type             = "ClusterIP"
    session_affinity = "None"
    port {
      name        = "http"
      port        = var.port
      protocol    = "TCP"
      target_port = var.port
    }
    selector = {
      component = local.component_name
    }
  }
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  data = {
    "grafana.ini" = <<-EOT

    [paths]
    data = /var/lib/grafana/
    logs = /var/log/grafana
    plugins = /var/lib/grafana/plugins
    provisioning = /etc/grafana/provisioning

    [analytics]
    check_for_updates = true

    [log]
    mode = console

    [grafana_net]
    url = https://grafana.net

    EOT
  }
}

resource "kubernetes_persistent_volume_claim" "persistent_volume_claim" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  spec {
    resources {
      requests = {
        storage = "2Gi"
      }
    }
    access_modes = [
      "ReadWriteOnce"
    ]
  }
}

resource "kubernetes_deployment" "deployment" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  spec {
    selector {
      match_labels = {
        component = local.component_name
      }
    }
    replicas = "1"
    strategy {
      type = "RollingUpdate"
    }
    template {
      metadata {
        labels = {
          component = local.component_name
        }
      }
      spec {
        security_context {
          run_as_user         = "472"
          run_as_group        = "472"
          fs_group            = "472"
          supplemental_groups = [0]
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.persistent_volume_claim.metadata[0].name
          }
        }
        container {
          name              = local.component_name
          image             = "grafana/grafana:8.3.4"
          image_pull_policy = "IfNotPresent"
          resources {
            requests = {
              cpu    = "125m"
              memory = "384Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "768Mi"
            }
          }
          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/grafana"
          }
          volume_mount {
            name       = "storage"
            mount_path = "/var/lib/grafana"
          }
          readiness_probe {
            http_get {
              path   = "/api/health"
              port   = var.port
              scheme = "HTTP"
            }
            timeout_seconds       = 2
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            failure_threshold     = 3
          }
          liveness_probe {
            http_get {
              path   = "/api/health"
              port   = var.port
              scheme = "HTTP"
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