locals {
  base_service_name = var.component_name == null ? var.app_name : "${var.app_name}-${var.component_name}"
  labels = {
    "app.kubernetes.io/name"      = var.app_name
    "app.kubernetes.io/component" = var.component_name
  }
}
locals {
  cluster_domain = var.cluster_domain

  service_name      = var.headless_only ? null : local.base_service_name
  service_namespace = var.headless_only ? null : var.namespace_name
  service_hostname  = var.headless_only ? null : "${local.service_name}.${local.service_namespace}.svc.${local.cluster_domain}"

  headless_service_name      = var.non_headless_only ? null : "${local.base_service_name}-headless"
  headless_service_namespace = var.non_headless_only ? null : var.namespace_name
  headless_service_hostname  = var.non_headless_only ? null : "${local.headless_service_name}.${local.headless_service_namespace}.svc.${local.cluster_domain}"
}
resource "kubernetes_service" "service" {
  count = var.headless_only ? 0 : 1
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
    labels    = local.labels
  }
  spec {
    type             = "ClusterIP"
    session_affinity = "None"
    dynamic "port" {
      for_each = var.ports
      content {
        name        = port.key
        protocol    = "TCP"
        port        = port.value.port
        target_port = port.value.target_port
      }
    }
    selector = local.labels
  }
}
resource "kubernetes_service" "headless_service" {
  count = var.non_headless_only ? 0 : 1
  metadata {
    name      = local.headless_service_name
    namespace = var.namespace_name
    labels    = local.labels
  }
  spec {
    type                        = "ClusterIP"
    session_affinity            = "None"
    cluster_ip                  = "None"
    publish_not_ready_addresses = true
    dynamic "port" {
      for_each = var.ports
      content {
        name        = port.key
        protocol    = "TCP"
        port        = port.value.port
        target_port = port.value.target_port
      }
    }
    selector = local.labels
  }
}