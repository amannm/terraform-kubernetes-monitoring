locals {

  config_filename = "agent.yaml"
  command         = ["/bin/agent"]
  args = [
    "-config.file=${local.volumes.config.mount_path}/${local.config_filename}",
    "-prometheus.wal-directory=${local.volumes.write-ahead-log.mount_path}",
    "-enable-features=integrations-next",
  ]

  cpu_min    = 50
  memory_min = 125
  memory_max = 350

  pod_environment_variables = {
    "HOSTNAME" = "spec.nodeName"
  }

  lifecycle = {
    min_readiness_time = 10
    max_readiness_time = 90
    max_cleanup_time   = 10
  }
  security = {
    uid                       = 0
    added_capabilities        = ["SYS_TIME"]
    read_only_root_filesystem = null
  }

  ports = {
    http = {
      port        = var.service_port
      target_port = var.service_port
    }
  }

  volumes = {
    "config" = {
      mount_path      = "/etc/agent"
      config_map_name = var.service_name
    }
    "write-ahead-log" = {
      mount_path = "/tmp/agent/wal"
      size_limit = null
    }
    "positions" = {
      mount_path = "/tmp/agent/positions"
      size_limit = null
    }
    "host-log" = {
      mount_path = "/var/log"
      host_path  = "/var/log"
    }
    "host-containers-log" = {
      mount_path = "/var/log/docker/containers"
      host_path  = "/var/log/docker/containers"
    }
    "host-id" = {
      mount_path = "/etc/machine-id"
      host_path  = "/etc/machine-id"
    }
    "proc" = {
      mount_path = "/host/proc"
      host_path  = "/proc"
    }
    "sys" = {
      mount_path = "/host/sys"
      host_path  = "/sys"
    }
    "root" = {
      mount_path = "/host/root"
      host_path  = "/"
    }
  }
}
resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = var.service_name
  }
  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "nodes/metrics", "services", "endpoints", "pods", "ingresses", "configmaps"]
    verbs      = ["get", "list", "watch"]
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

module "service_account" {
  source            = "../common/cluster-service-account"
  namespace_name    = var.namespace_name
  service_name      = var.service_name
  cluster_role_name = kubernetes_cluster_role.cluster_role.metadata[0].name
}

module "agent_config" {
  source                = "./module/config"
  namespace_name        = var.namespace_name
  service_name          = var.service_name
  stateless_node_labels = var.stateless_node_labels
  config_filename       = local.config_filename
  agent_container_port  = var.service_port
  node_exporter_config = {
    host_root_volume_mount_path = local.volumes.root.mount_path
    host_sys_volume_mount_path  = local.volumes.sys.mount_path
    host_proc_volume_mount_path = local.volumes.proc.mount_path
  }
  metrics_config = var.metrics_remote_write_url == null ? null : {
    agentctl_container_image = var.agentctl_container_image
    agent_host               = "${module.service.headless_service_hostname}:${var.service_port}"
    remote_write_url         = var.metrics_remote_write_url
    etcd_host                = var.etcd_host
    partition_by_labels      = var.partition_by_labels
  }
  logs_config = var.logs_remote_write_url == null ? null : {
    positions_volume_mount_path = local.volumes.positions.mount_path
    remote_write_url            = var.logs_remote_write_url
  }
}

module "service" {
  source             = "../common/service"
  cluster_domain     = var.cluster_domain
  namespace_name     = var.namespace_name
  service_name       = var.service_name
  ports              = local.ports
  headless_only      = true
  wait_for_readiness = true
}

resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    min_ready_seconds = local.lifecycle.min_readiness_time
    selector {
      match_labels = {
        component = var.service_name
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 1
      }
    }
    template {
      metadata {
        name = var.service_name
        labels = {
          component = var.service_name
        }
      }
      spec {
        termination_grace_period_seconds = local.lifecycle.max_cleanup_time
        host_pid                         = true
        host_network                     = true
        dns_policy                       = "ClusterFirstWithHostNet"
        service_account_name             = module.service_account.name
        dynamic "volume" {
          for_each = local.volumes
          content {
            name = volume.key
            dynamic "host_path" {
              for_each = { for k, v in volume.value : k => v if k == "host_path" }
              content {
                path = host_path.value
              }
            }
            dynamic "empty_dir" {
              for_each = { for k, v in volume.value : k => v if k == "size_limit" }
              content {
                size_limit = empty_dir.value
              }
            }
            dynamic "config_map" {
              for_each = { for k, v in volume.value : k => v if k == "config_map_name" }
              content {
                name = config_map.value
              }
            }
          }
        }
        container {
          name              = var.service_name
          command           = local.command
          args              = local.args
          image             = var.agent_container_image
          image_pull_policy = "IfNotPresent"
          security_context {
            privileged                 = local.security.uid == 0
            allow_privilege_escalation = local.security.uid == 0
            run_as_non_root            = local.security.uid != 0
            run_as_user                = local.security.uid
            run_as_group               = local.security.uid
            read_only_root_filesystem  = local.security.read_only_root_filesystem
            capabilities {
              add  = local.security.added_capabilities
              drop = local.security.uid != 0 ? ["ALL"] : []
            }
          }
          resources {
            requests = {
              cpu    = "${local.cpu_min}m"
              memory = "${local.memory_min}Mi"
            }
            limits = {
              memory = "${local.memory_max}Mi"
            }
          }
          dynamic "env" {
            for_each = local.pod_environment_variables
            content {
              name = env.key
              value_from {
                field_ref {
                  field_path = env.value
                }
              }
            }
          }
          dynamic "port" {
            for_each = local.ports
            content {
              name           = port.key
              protocol       = "TCP"
              container_port = port.value["target_port"]
            }
          }
          dynamic "volume_mount" {
            for_each = local.volumes
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value["mount_path"]
              read_only  = lookup(volume_mount.value, "host_path", "") != ""
            }
          }
        }
      }
    }
  }
}