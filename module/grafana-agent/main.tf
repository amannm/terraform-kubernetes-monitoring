locals {
  config_filename          = "agent.yaml"
  config_volume_name       = "config"
  config_volume_mount_path = "/etc/agent"

  wal_volume_name       = "write-ahead-log"
  wal_volume_mount_path = "/tmp/agent/wal"

  host_volumes = {
    "host-log" = {
      host_path  = "/var/log"
      mount_path = "/var/log"
    }
    "host-containers-log" = {
      host_path  = "/var/lob/docker/containers"
      mount_path = "/var/lob/docker/containers"
    }
    "host-id" = {
      host_path  = "/etc/machine-id"
      mount_path = "/etc/machine-id"
    }
    "proc" = {
      host_path  = "/proc"
      mount_path = "/host/proc"
    }
    "sys" = {
      host_path  = "/sys"
      mount_path = "/host/sys"
    }
    "root" = {
      host_path  = "/"
      mount_path = "/host/root"
    }
  }
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
}

resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = var.resource_name
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
    name = var.resource_name
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

module "grafana_agent_config" {
  source                      = "./module/config"
  namespace_name              = var.namespace_name
  server_container_port       = var.container_port
  metrics_remote_write_url    = var.metrics_remote_write_url
  host_root_volume_mount_path = local.host_volumes.root.mount_path
  host_sys_volume_mount_path  = local.host_volumes.sys.mount_path
  host_proc_volume_mount_path = local.host_volumes.proc.mount_path
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = module.grafana_agent_config.yaml
  }
}

resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
  spec {
    strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = {
        name = var.resource_name
      }
    }
    template {
      metadata {
        labels = {
          name = var.resource_name
        }
      }
      spec {
        termination_grace_period_seconds = 10
        host_pid                         = true
        host_network                     = true
        dns_policy                       = "ClusterFirstWithHostNet"
        service_account_name             = kubernetes_service_account.service_account.metadata[0].name
        volume {
          name = local.config_volume_name
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        volume {
          name = local.wal_volume_name
          empty_dir {}
        }
        dynamic "volume" {
          for_each = local.host_volumes
          content {
            name = volume.key
            host_path {
              path = volume.value["host_path"]
            }
          }
        }
        container {
          name              = var.resource_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/agent"]
          args = [
            "-config.file=${local.config_volume_mount_path}/${local.config_filename}",
            "-prometheus.wal-directory=${local.wal_volume_mount_path}",
            "-enable-features=integrations-next",
          ]
          port {
            protocol       = "TCP"
            container_port = var.container_port
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "125Mi"
            }
            limits = {
              memory = "300Mi"
            }
          }
          security_context {
            privileged  = true
            run_as_user = "0"
            capabilities {
              add = ["SYS_TIME"]
            }
          }
          env {
            name = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          volume_mount {
            name       = local.config_volume_name
            mount_path = local.config_volume_mount_path
          }
          volume_mount {
            name       = local.wal_volume_name
            mount_path = local.wal_volume_mount_path
          }
          dynamic "volume_mount" {
            for_each = local.host_volumes
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value["mount_path"]
              read_only  = true
            }
          }
        }
      }
    }
  }
}