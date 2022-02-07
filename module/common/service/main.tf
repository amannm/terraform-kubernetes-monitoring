locals {
  cluster_domain = var.cluster_domain

  service_name      = var.headless_only ? null : var.service_name
  service_namespace = var.headless_only ? null : var.namespace_name
  service_hostname  = var.headless_only ? null : "${local.service_name}.${local.service_namespace}.svc.${local.cluster_domain}"

  headless_service_name      = var.non_headless_only ? null : "${var.service_name}-headless"
  headless_service_namespace = var.non_headless_only ? null : var.namespace_name
  headless_service_hostname  = var.non_headless_only ? null : "${local.headless_service_name}.${local.headless_service_namespace}.svc.${local.cluster_domain}"
}
resource "kubernetes_service" "service" {
  count = var.headless_only ? 0 : 1
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
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
    selector = {
      component = var.service_name
    }
  }
}
resource "kubernetes_service" "headless_service" {
  count = var.non_headless_only ? 0 : 1
  metadata {
    name      = "${var.service_name}-headless"
    namespace = var.namespace_name
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
    selector = {
      component = var.service_name
    }
  }
}