locals {
  proc_volume_name       = "proc"
  proc_volume_mount_path = "/host/proc"
  proc_host_path         = "/proc"

  sys_volume_name       = "sys"
  sys_volume_mount_path = "/host/sys"
  sys_host_path         = "/sys"

  root_volume_name       = "root"
  root_volume_mount_path = "/host/root"
  root_host_path         = "/"
}

resource "kubernetes_service" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    type       = "ClusterIP"
    cluster_ip = "None"
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

resource "kubernetes_role" "role" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  rule {
    api_groups     = ["extensions"]
    resources      = ["podsecuritypolicies"]
    verbs          = ["use"]
    resource_names = [var.service_name]
  }
}

resource "kubernetes_role_binding" "role_binding" {
  metadata {
    name      = var.service_name
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
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
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
        host_pid             = true
        service_account_name = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          fs_group        = "65534"
          run_as_group    = "65534"
          run_as_user     = "65534"
          run_as_non_root = true
        }
        volume {
          name = local.proc_volume_name
          host_path {
            path = local.proc_host_path
          }
        }
        volume {
          name = local.sys_volume_name
          host_path {
            path = local.sys_host_path
          }
        }
        volume {
          name = local.root_volume_name
          host_path {
            path = local.root_host_path
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          args = [
            "--path.procfs=${local.proc_volume_mount_path}",
            "--path.sysfs=${local.sys_volume_mount_path}",
            "--path.rootfs=${local.root_volume_mount_path}",
            "--web.listen-address=:${var.container_port}",
            "--web.telemetry-path=/metrics",
          ]
          port {
            protocol       = "TCP"
            container_port = var.container_port
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "125Mi"
            }
            limits = {
              cpu    = "125m"
              memory = "250Mi"
            }
          }
          volume_mount {
            name              = local.proc_volume_name
            mount_path        = local.proc_volume_mount_path
            mount_propagation = "HostToContainer"
            read_only         = true
          }
          volume_mount {
            name              = local.sys_volume_name
            mount_path        = local.sys_volume_mount_path
            mount_propagation = "HostToContainer"
            read_only         = true
          }
          volume_mount {
            name              = local.root_volume_name
            mount_path        = local.root_volume_mount_path
            mount_propagation = "HostToContainer"
            read_only         = true
          }
        }
      }
    }
  }
}