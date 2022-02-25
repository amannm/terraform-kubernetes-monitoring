terraform {
  experiments = [
    module_variable_optional_attrs
  ]
}
locals {
  preemptible_node_label = var.preemptible_node_label_name != null && var.preemptible_node_label_value != null ? {
    (var.preemptible_node_label_name) = var.preemptible_node_label_value
  } : {}
}
locals {
  service_name        = "${var.system_name}-${var.component_name}"
  storage_volume_name = "storage"
  args = [
    "-config.file=${local.volumes.config.mount_path}/${var.config_filename}",
    "-target=${var.component_name}",
  ]
  cpu_min    = var.pod_resources.cpu_min
  memory_min = var.pod_resources.memory_min
  memory_max = var.pod_resources.memory_max
  ports = {
    http = {
      port        = var.service_http_port
      target_port = var.service_http_port
    }
    grpc = {
      port        = var.service_grpc_port
      target_port = var.service_grpc_port
    }
  }
  security = {
    uid                       = 10001
    added_capabilities        = []
    read_only_root_filesystem = true
  }
  lifecycle = {
    min_readiness_time = var.pod_lifecycle.min_readiness_time
    max_readiness_time = var.pod_lifecycle.max_readiness_time
    max_cleanup_time   = var.pod_lifecycle.max_cleanup_time
    shutdown_hook_path = var.pod_lifecycle.shutdown_hook_path
  }
  probes = {
    port                   = var.service_http_port
    readiness_path         = "/ready"
    liveness_path          = "/ready"
    readiness_polling_rate = 10
    liveness_polling_rate  = 30
  }
  volumes = {
    "config" = {
      mount_path      = var.config_mount_path
      config_map_name = var.config_map_name
    }
    (local.storage_volume_name) = {
      mount_path = var.storage_mount_path
    }
  }
}

module "service" {
  source         = "../service"
  namespace_name = var.namespace_name
  service_name   = local.service_name
  ports          = local.ports
}

resource "kubernetes_pod_disruption_budget" "pdb" {
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
  }
  spec {
    max_unavailable = 1
    selector {
      match_labels = {
        component = local.service_name
      }
    }
  }
}

resource "kubernetes_stateful_set" "deployment" {
  spec {
    service_name = module.service.headless_service_name
    replicas     = var.replicas
    update_strategy {
      rolling_update {
        partition = 0
      }
    }
    volume_claim_template {
      metadata {
        name      = local.storage_volume_name
        namespace = var.namespace_name
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "${var.storage_volume_size}G"
          }
        }
      }
    }
    template {
      spec {
        service_account_name             = var.service_account_name
        termination_grace_period_seconds = local.lifecycle.max_cleanup_time
        security_context {
          fs_group = local.security.uid
        }
        container {
          name              = local.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          args              = local.args
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
          dynamic "lifecycle" {
            for_each = { for k, v in local.lifecycle : k => v if k == "shutdown_hook_path" && v != null }
            content {
              pre_stop {
                http_get {
                  path = lifecycle.value
                  port = local.ports.http.target_port
                }
              }
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
          readiness_probe {
            http_get {
              path = local.probes.readiness_path
              port = local.probes.port
            }
            initial_delay_seconds = local.lifecycle.min_readiness_time
            period_seconds        = local.probes.readiness_polling_rate
            success_threshold     = 1
            failure_threshold     = ceil(local.lifecycle.max_readiness_time / local.probes.readiness_polling_rate)
            timeout_seconds       = 5
          }
          #          liveness_probe {
          #            http_get {
          #              path = local.probes.liveness_path
          #              port = local.probes.port
          #            }
          #            initial_delay_seconds = local.lifecycle.max_readiness_time
          #            period_seconds        = local.probes.liveness_polling_rate
          #            success_threshold     = 1
          #            failure_threshold     = 3
          #            timeout_seconds       = 1
          #          }
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
        dynamic "volume" {
          for_each = local.volumes
          content {
            name = volume.key
            dynamic "empty_dir" {
              for_each = { for k, v in volume.value : k => v if k == "size_limit" }
              content {
                size_limit = "${empty_dir.value}G"
              }
            }
            dynamic "config_map" {
              for_each = { for k, v in volume.value : k => v if k == "config_map_name" }
              content {
                name = config_map.value
              }
            }
            dynamic "persistent_volume_claim" {
              for_each = { for k, v in volume.value : k => v if k == "persistent_volume_claim_name" }
              content {
                name = persistent_volume_claim.value
              }
            }
          }
        }
        affinity {
          dynamic "node_affinity" {
            for_each = { for k, v in local.preemptible_node_label : k => v }
            content {
              required_during_scheduling_ignored_during_execution {
                node_selector_term {
                  match_expressions {
                    key      = node_affinity.key
                    operator = "NotIn"
                    values   = [node_affinity.value]
                  }
                }
              }
            }
          }
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              topology_key = "kubernetes.io/hostname"
              label_selector {
                match_labels = {
                  component = local.service_name
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                topology_key = "topology.kubernetes.io/zone"
                label_selector {
                  match_labels = {
                    component = local.service_name
                  }
                }
              }
            }
          }
        }
      }
      metadata {
        labels = {
          component = local.service_name
        }
        annotations = {
          "checksum/config" = var.config_checksum
        }
      }
    }
    selector {
      match_labels = {
        component = local.service_name
      }
    }
  }
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
    labels = {
      component = local.service_name
    }
  }
}