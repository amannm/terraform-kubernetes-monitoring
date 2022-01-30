locals {
  enabled_resources = {
    certificatesigningrequests      = ["certificates.k8s.io"]
    configmaps                      = [""]
    cronjobs                        = ["batch"]
    daemonsets                      = ["extensions", "apps"]
    deployments                     = ["extensions", "apps"]
    endpoints                       = [""]
    horizontalpodautoscalers        = ["autoscaling"]
    ingresses                       = ["extensions", "networking.k8s.io"]
    jobs                            = ["batch"]
    limitranges                     = [""]
    mutatingwebhookconfigurations   = ["admissionregistration.k8s.io"]
    namespaces                      = [""]
    networkpolicies                 = ["networking.k8s.io"]
    nodes                           = [""]
    persistentvolumeclaims          = [""]
    persistentvolumes               = [""]
    poddisruptionbudgets            = ["policy"]
    pods                            = [""]
    replicasets                     = ["extensions", "apps"]
    replicationcontrollers          = [""]
    resourcequotas                  = [""]
    secrets                         = [""]
    services                        = [""]
    statefulsets                    = ["apps"]
    storageclasses                  = ["storage.k8s.io"]
    validatingwebhookconfigurations = ["admissionregistration.k8s.io"]
    volumeattachments               = ["storage.k8s.io"]
  }
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
  dynamic "rule" {
    for_each = local.enabled_resources
    content {
      api_groups = rule.value
      resources  = [rule.key]
      verbs      = ["list", "watch"]
    }
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
        termination_grace_period_seconds = 10
        service_account_name             = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          run_as_user  = "65534"
          run_as_group = "65534"
          fs_group     = "65534"
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--port=${var.container_port}",
            "--resources=${join(",", keys(local.enabled_resources))}",
            "--telemetry-port=${var.container_metrics_port}"
          ]
          port {
            protocol       = "TCP"
            container_port = var.container_port
          }
          port {
            protocol       = "TCP"
            container_port = var.container_metrics_port
          }
          resources {
            requests = {
              cpu : "50m"
              memory : "125Mi"
            }
            limits = {
              memory : "250Mi"
            }
          }
          readiness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.container_port
              path   = "/"
            }
            timeout_seconds       = 5
            initial_delay_seconds = 5
          }
          liveness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.container_port
              path   = "/healthz"
            }
            timeout_seconds       = 5
            initial_delay_seconds = 5
          }
        }
      }
    }
  }
}