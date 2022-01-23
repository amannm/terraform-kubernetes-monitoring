locals {
  component_name = "kube-state-metrics"
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
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          run_as_user  = "65534"
          run_as_group = "65534"
          fs_group     = "65534"
        }
        container {
          name              = local.component_name
          image             = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
          image_pull_policy = "IfNotPresent"
          args = [
            "--port=${var.port}",
            "--resources=${join(",", keys(local.enabled_resources))}"
          ]
          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = var.port
              scheme = "HTTP"
            }
            timeout_seconds       = 5
            initial_delay_seconds = 5
          }
          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = var.port
              scheme = "HTTP"
            }
            timeout_seconds       = 5
            initial_delay_seconds = 5
          }
        }
      }
    }
  }
}