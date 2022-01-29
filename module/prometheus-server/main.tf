locals {

  config_filename = "prometheus.yml"

  config_volume_name       = "config"
  config_volume_mount_path = "/etc/config"

  storage_volume_name       = "storage"
  storage_volume_mount_path = "/data"
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
      port        = var.service_port
      protocol    = "TCP"
      target_port = var.server_container_port
    }
    selector = {
      component = var.service_name
    }
  }
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
}

resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = var.service_name
  }
  rule {
    api_groups = [""]
    verbs      = ["get", "list", "watch"]
    resources  = ["nodes", "nodes/proxy", "nodes/metrics", "services", "endpoints", "pods", "ingresses", "configmaps"]
  }
  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses/status", "ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
  metadata {
    name = var.service_name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.service_account.metadata[0].name
    namespace = var.namespace_name
  }
  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
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

module "prometheus_config" {
  source                          = "./module/config"
  namespace_name                  = var.namespace_name
  server_container_port           = var.server_container_port
  configmap_reload_container_port = var.configmap_reload_container_port
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = module.prometheus_config.yaml
    "recording_rules.yml"   = ""
    "alerting_rules.yml"    = ""
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
        enable_service_links             = true
        service_account_name             = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          fs_group        = "65534"
          run_as_group    = "65534"
          run_as_non_root = true
          run_as_user     = "65534"
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
          image             = var.server_container_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--config.file=${local.config_volume_mount_path}/${local.config_filename}",
            "--storage.tsdb.path=${local.storage_volume_mount_path}",
            "--storage.tsdb.retention=${var.storage_retention_days}d",
            "--web.enable-lifecycle",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
          ]
          port {
            protocol       = "TCP"
            container_port = var.server_container_port
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "100Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "250Mi"
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
            period_seconds        = 5
            timeout_seconds       = 4
            failure_threshold     = 3
            success_threshold     = 1
          }
          liveness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.server_container_port
              path   = "/-/healthy"
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            timeout_seconds       = 10
            failure_threshold     = 3
            success_threshold     = 1
          }
        }
        container {
          name              = "${var.service_name}-configmap-reload"
          image             = var.configmap_reload_container_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--volume-dir=${local.config_volume_mount_path}",
            "--webhook-url=http://localhost:${var.server_container_port}/-/reload",
            "--webhook-method=POST",
            "--webhook-status-code=200",
            "--webhook-retries=1",
            "--web.listen-address=:${var.configmap_reload_container_port}",
            "--web.telemetry-path=/metrics",
          ]
          resources {
            requests = {
              cpu    = "25m"
              memory = "50Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "100Mi"
            }
          }
          port {
            protocol       = "TCP"
            container_port = var.configmap_reload_container_port
          }
          volume_mount {
            name       = local.config_volume_name
            mount_path = local.config_volume_mount_path
            read_only  = true
          }
        }
      }
    }
  }
}