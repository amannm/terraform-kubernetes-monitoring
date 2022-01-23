locals {
  component_name = "prometheus-server"
}

resource "kubernetes_service" "service" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
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

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
}

resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = local.component_name
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
    name = local.component_name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.service_account.metadata[0].name
    namespace = var.namespace_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_role.metadata[0].name
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
        storage = "8Gi"
      }
    }
    access_modes = [
      "ReadWriteOnce"
    ]
  }
}

module "prometheus_config" {
  source                          = "module/config"
  namespace_name                  = var.namespace_name
  port                            = var.port
  kube_state_metrics_service_name = var.kube_state_metrics_service_name
  kube_state_metrics_service_port = var.kube_state_metrics_service_port
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  data = {
    "prometheus.yml"      = module.prometheus_config.yaml
    "recording_rules.yml" = ""
    "alerting_rules.yml"  = ""
  }
}

resource "kubernetes_deployment" "deployment" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  spec {
    replicas = "1"
    strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = {
        component = local.component_name
      }
    }
    template {
      metadata {
        labels = {
          component = local.component_name
        }
      }
      spec {
        termination_grace_period_seconds = 300
        host_network                     = false
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
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        volume {
          name = "storage-volume"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.persistent_volume_claim.metadata[0].name
          }
        }
        container {
          name              = local.component_name
          image             = "quay.io/prometheus/prometheus:v2.31.1"
          image_pull_policy = "IfNotPresent"
          args = [
            "--config.file=/etc/config/prometheus.yml",
            "--storage.tsdb.path=/data",
            "--storage.tsdb.retention=15d",
            "--web.enable-lifecycle",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
          ]
          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }
          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config"
          }
          volume_mount {
            name       = "storage-volume"
            mount_path = "/data"
          }
          readiness_probe {
            http_get {
              path   = "/-/ready"
              port   = var.port
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            period_seconds        = 5
            timeout_seconds       = 4
            failure_threshold     = 3
            success_threshold     = 1
          }
          liveness_probe {
            http_get {
              path   = "/-/healthy"
              port   = var.port
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            timeout_seconds       = 10
            failure_threshold     = 3
            success_threshold     = 1
          }
        }
      }
    }
  }
}