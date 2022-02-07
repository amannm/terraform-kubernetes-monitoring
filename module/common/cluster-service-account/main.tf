locals {
  service_account_name = kubernetes_service_account.service_account.metadata[0].name
}
resource "kubernetes_service_account" "service_account" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  automount_service_account_token = true
}
resource "kubernetes_cluster_role_binding" "cluster_role_binding" {
  metadata {
    name = var.service_name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.service_account.metadata[0].name
    namespace = var.namespace_name
  }
  role_ref {
    kind      = "ClusterRole"
    name      = var.cluster_role_name
    api_group = "rbac.authorization.k8s.io"
  }
}