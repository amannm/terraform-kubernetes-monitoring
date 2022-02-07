locals {
  persistent_volume_claim_name = kubernetes_persistent_volume_claim.persistent_volume_claim.metadata[0].name
}
resource "kubernetes_persistent_volume_claim" "persistent_volume_claim" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    resources {
      requests = {
        storage = "${var.size}Gi"
      }
    }
    access_modes = [
      "ReadWriteOnce"
    ]
  }
}