locals {
  component_name = "prometheus-node-exporter"
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
    type       = "ClusterIP"
    cluster_ip = "None"
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

resource "kubernetes_role" "role" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  rule {
    api_groups     = ["extensions"]
    resources      = ["podsecuritypolicies"]
    verbs          = ["use"]
    resource_names = [local.component_name]
  }
}

resource "kubernetes_role_binding" "role_binding" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.role.metadata[0].name
  }
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.service_account.metadata[0].name
  }
}

resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name      = local.component_name
    namespace = var.namespace_name
  }
  spec {
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
        host_network         = false
        host_pid             = true
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          fs_group        = "65534"
          run_as_group    = "65534"
          run_as_non_root = true
          run_as_user     = "65534"
        }
        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "root"
          host_path {
            path = "/"
          }
        }
        container {
          name              = local.component_name
          image             = "quay.io/prometheus/node-exporter:v1.3.0"
          image_pull_policy = "IfNotPresent"
          args = [
            "--path.procfs=/host/proc",
            "--path.sysfs=/host/sys",
            "--path.rootfs=/host/root",
          ]
          port {
            name           = "http"
            container_port = var.port
            host_port      = var.port
          }
          volume_mount {
            name       = "proc"
            mount_path = "/host/proc"
            read_only  = true
          }
          volume_mount {
            name       = "sys"
            mount_path = "/host/sys"
            read_only  = true
          }
          volume_mount {
            name              = "root"
            mount_path        = "/host/root"
            mount_propagation = "HostToContainer"
            read_only         = true
          }
        }
      }
    }
  }
}