terraform {
  experiments = [
    module_variable_optional_attrs
  ]
}
locals {
  service_account_name = kubernetes_service_account.service_account.metadata[0].name
}
resource "kubernetes_service_account" "service_account" {
  metadata {
    name        = var.service_name
    namespace   = var.namespace_name
    annotations = var.annotations
  }
  automount_service_account_token = true
}
resource "kubernetes_role_binding" "role_binding" {
  count = var.role_name == null ? 0 : 1
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
    name      = var.role_name
    api_group = "rbac.authorization.k8s.io"
  }
}