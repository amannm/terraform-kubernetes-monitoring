locals {
  preemptible_node_label = var.preemptible_node_label_name != null && var.preemptible_node_label_value != null ? {
    (var.preemptible_node_label_name) = var.preemptible_node_label_value
  } : {}
}
locals {
  health_check_path = "/api/health"

  config_volume_name       = "config"
  config_volume_mount_path = "/etc/grafana"

  storage_volume_name       = "storage"
  storage_volume_mount_path = "/var/lib/grafana"

  service_host = "${module.service.non_headless_service_hostname}:${var.service_port}"
}

module "service" {
  source         = "../common/service"
  namespace_name = var.namespace_name
  service_name   = var.service_name
  ports = {
    http = {
      port        = var.service_port
      target_port = var.container_port
    }
  }
}

// TODO: break out all config
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    "grafana.ini" = <<-EOT

    [paths]
    data = ${local.storage_volume_mount_path}
    temp_data_lifetime = 24h
    logs = ${local.storage_volume_mount_path}/log
    plugins = ${local.storage_volume_mount_path}/plugins
    provisioning = ${local.config_volume_mount_path}/provisioning

    [server]
    protocol = http
    http_port = ${var.container_port}

    [analytics]
    reporting_enabled = false
    check_for_updates = true

    [snapshots]
    external_enabled = false

    [log]
    mode = console
    level = info

    [metrics]
    enabled = true

    EOT
  }
}

resource "kubernetes_stateful_set" "stateful_set" {
  spec {
    replicas     = 1
    service_name = module.service.headless_service_name
    update_strategy {
      rolling_update {
        partition = 0
      }
    }
    volume_claim_template {
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "${var.storage_volume_size}Gi"
          }
        }
      }
      metadata {
        name      = local.storage_volume_name
        namespace = var.namespace_name
      }
    }
    template {
      spec {
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
              label_selector {
                match_labels = {
                  component = var.service_name
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    component = var.service_name
                  }
                }
                topology_key = "failure-domain.beta.kubernetes.io/zone"
              }
            }
          }
        }
        termination_grace_period_seconds = 30
        security_context {
          run_as_user         = "472"
          run_as_group        = "472"
          fs_group            = "472"
          supplemental_groups = [0]
        }
        volume {
          name = local.config_volume_name
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          resources {
            requests = {
              cpu    = "100m"
              memory = "85Mi"
            }
            limits = {
              memory = "120Mi"
            }
          }
          port {
            protocol       = "TCP"
            container_port = var.container_port
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
              port   = var.container_port
              path   = local.health_check_path
            }
            timeout_seconds       = 2
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            failure_threshold     = 3
          }
          liveness_probe {
            http_get {
              scheme = "HTTP"
              port   = var.container_port
              path   = local.health_check_path
            }
            timeout_seconds       = 30
            initial_delay_seconds = 60
            period_seconds        = 10
            success_threshold     = 1
            failure_threshold     = 10
          }
        }
      }
      metadata {
        labels = {
          component = var.service_name
        }
      }
    }
    selector {
      match_labels = {
        component = var.service_name
      }
    }
  }
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
}