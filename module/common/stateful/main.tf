terraform {
  experiments = [
    module_variable_optional_attrs
  ]
}
locals {
  service_name = var.component_name == null ? var.app_name : "${var.app_name}-${var.component_name}"
  labels = {
    "app.kubernetes.io/name"      = var.app_name
    "app.kubernetes.io/component" = var.component_name
  }
}
module "service" {
  source             = "../service"
  cluster_domain     = var.cluster_domain
  namespace_name     = var.namespace_name
  app_name           = var.app_name
  component_name     = var.component_name
  ports              = { for k, v in var.ports : k => v if v.port != null }
  wait_for_readiness = var.wait_for_readiness
}
resource "kubernetes_pod_disruption_budget" "pdb" {
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
  }
  spec {
    max_unavailable = 1
    selector {
      match_labels = local.labels
    }
  }
}
resource "kubernetes_stateful_set" "deployment" {
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
    labels    = local.labels
  }
  spec {
    service_name = module.service.headless_service_name
    replicas     = var.replicas
    selector {
      match_labels = local.labels
    }
    update_strategy {
      rolling_update {
        partition = 0
      }
    }
    dynamic "volume_claim_template" {
      for_each = var.persistent_volumes
      content {
        metadata {
          name      = volume_claim_template.key
          namespace = var.namespace_name
        }
        spec {
          access_modes = ["ReadWriteOnce"]
          resources {
            requests = {
              storage = "${volume_claim_template.value.size}G"
            }
          }
        }
      }
    }
    template {
      metadata {
        labels      = local.labels
        annotations = { for k, v in var.config_volumes : "checksum/${k}" => v.config_checksum }
      }
      spec {
        service_account_name             = var.service_account_name
        termination_grace_period_seconds = var.pod_lifecycle.max_cleanup_time
        dynamic "security_context" {
          for_each = var.pod_security_context == null ? [] : [var.pod_security_context]
          content {
            fs_group            = var.pod_security_context.uid
            supplemental_groups = var.pod_security_context.supplemental_groups
          }
        }
        container {
          name              = local.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          command           = var.command
          args              = var.args
          dynamic "security_context" {
            for_each = var.pod_security_context == null ? [] : [var.pod_security_context]
            content {
              privileged                 = var.pod_security_context.uid == 0
              allow_privilege_escalation = var.pod_security_context.uid == 0
              run_as_non_root            = var.pod_security_context.uid != 0
              run_as_user                = var.pod_security_context.uid
              run_as_group               = var.pod_security_context.uid
              read_only_root_filesystem  = var.pod_security_context.read_only_root_filesystem
              capabilities {
                add  = var.pod_security_context.added_capabilities
                drop = var.pod_security_context.uid != 0 ? ["ALL"] : []
              }
            }
          }
          dynamic "lifecycle" {
            for_each = { for k, v in var.pod_lifecycle : k => v if k == "shutdown_hook_path" && v != null }
            content {
              pre_stop {
                http_get {
                  path = lifecycle.value
                  port = var.ports["http"].target_port
                }
              }
            }
          }
          dynamic "lifecycle" {
            for_each = { for k, v in var.pod_lifecycle : k => v if k == "shutdown_exec_command" && v != null }
            content {
              pre_stop {
                exec {
                  command = lifecycle.value
                }
              }
            }
          }
          resources {
            requests = {
              cpu    = "${var.pod_resources.cpu_min}m"
              memory = "${var.pod_resources.memory_min}Mi"
            }
            limits = {
              memory = "${var.pod_resources.memory_max}Mi"
            }
          }
          readiness_probe {
            http_get {
              path = var.pod_probes.readiness_path
              port = var.pod_probes.port
            }
            initial_delay_seconds = var.pod_lifecycle.min_readiness_time
            period_seconds        = var.pod_probes.readiness_polling_rate
            success_threshold     = 1
            failure_threshold     = ceil(var.pod_lifecycle.max_readiness_time / var.pod_probes.readiness_polling_rate)
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
            for_each = var.ports
            content {
              name           = port.key
              protocol       = "TCP"
              container_port = port.value.target_port
            }
          }
          dynamic "volume_mount" {
            for_each = var.config_volumes
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value.mount_path
            }
          }
          dynamic "volume_mount" {
            for_each = var.persistent_volumes
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value.mount_path
            }
          }
          dynamic "env" {
            for_each = [for v in [var.pod_name_env_var] : v if v != null]
            content {
              name = env.value
              value_from {
                field_ref {
                  field_path = "metadata.name"
                }
              }
            }
          }
        }
        dynamic "volume" {
          for_each = var.config_volumes
          content {
            name = volume.key
            config_map {
              name = volume.value.config_map_name
            }
          }
        }
        affinity {
          dynamic "node_affinity" {
            for_each = var.stateless_node_labels
            content {
              required_during_scheduling_ignored_during_execution {
                node_selector_term {
                  match_expressions {
                    key      = node_affinity.key
                    operator = "NotIn"
                    values   = node_affinity.value
                  }
                }
              }
            }
          }
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              topology_key = "kubernetes.io/hostname"
              label_selector {
                match_labels = local.labels
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                topology_key = "topology.kubernetes.io/zone"
                label_selector {
                  match_labels = local.labels
                }
              }
            }
          }
        }
      }
    }
  }
}