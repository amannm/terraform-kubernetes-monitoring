resource "kubernetes_pod_security_policy" "pod_security_policy" {
  metadata {
    name = var.service_name
  }
  spec {
    required_drop_capabilities = ["ALL"]
    volumes = [
      "configMap", "emptyDir", "persistentVolumeClaim", "secret", "projected", "downwardAPI"
    ]
    se_linux {
      rule = "RunAsAny"
    }
    run_as_user {
      rule = "MustRunAsNonRoot"
    }
    fs_group {
      rule = "MustRunAs"
      range {
        min = 1
        max = 65535
      }
    }
    read_only_root_filesystem = true
    supplemental_groups {
      rule = "MustRunAs"
      range {
        min = 1
        max = 65535
      }
    }
  }
}

locals {
  config_filename = "loki.yaml"

  config_volume_name       = "config"
  config_volume_mount_path = "/etc/config"

  storage_volume_name       = "storage"
  storage_volume_mount_path = "/data"
}

module "loki_config" {
  source = "./module/config"

  etcd_host    = var.etcd_host
  http_port    = var.container_port
  storage_path = local.storage_volume_mount_path
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = module.loki_config.yaml
  }
}

resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  automount_service_account_token = true
}

resource "kubernetes_role" "role" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  rule {
    verbs          = ["use"]
    api_groups     = ["extensions"]
    resources      = ["podsecuritypolicies"]
    resource_names = [var.service_name]
  }
}
resource "kubernetes_role_binding" "role_binding" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.service_account.metadata[0].name
  }
  role_ref {
    kind      = "Role"
    name      = kubernetes_role.role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}
resource "kubernetes_service" "headless_service" {
  metadata {
    name      = "${var.service_name}-headless"
    namespace = var.namespace_name
  }
  spec {
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
resource "kubernetes_service" "service" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    type = "ClusterIP"
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
resource "kubernetes_persistent_volume_claim" "persistent_volume_claim" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    resources {
      requests = {
        storage = "${var.storage_volume_size}Gi"
      }
    }
    access_modes = [
      "ReadWriteOnce"
    ]
  }
}
resource "kubernetes_deployment" "deployment" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
    labels = {
      component = var.service_name
    }
  }
  spec {
    replicas = 1
    strategy {
      rolling_update {
        max_unavailable = 0
        max_surge       = 1
      }
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
        termination_grace_period_seconds = 4800
        service_account_name             = kubernetes_service_account.service_account.metadata[0].name
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
        }
        volume {
          name = local.config_volume_name
          config_map {
            name = kubernetes_config_map.config_map.metadata[0].name
          }
        }
        volume {
          name = local.storage_volume_name
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.persistent_volume_claim.metadata[0].name
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          security_context {
            read_only_root_filesystem = true
          }
          args = [
            "-config.file=${local.config_volume_mount_path}/${local.config_filename}"
          ]
          port {
            protocol       = "TCP"
            container_port = var.container_port
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "100Mi"
            }
            limits = {
              memory = "300Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/ready"
              port = var.container_port
            }
            initial_delay_seconds = 120
            period_seconds        = 20
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = var.container_port
            }
            initial_delay_seconds = 180
            period_seconds        = 60
          }
          volume_mount {
            name       = local.config_volume_name
            mount_path = local.config_volume_mount_path
          }
          volume_mount {
            name       = local.storage_volume_name
            mount_path = local.storage_volume_mount_path
          }
        }
      }
    }
  }
}