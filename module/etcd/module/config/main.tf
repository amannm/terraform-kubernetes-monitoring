# https://etcd.io/docs/v3.5/op-guide/configuration/
locals {
  rendered = yamlencode({
    "listen-client-urls"                            = "http://0.0.0.0:${var.client_port}"
    "listen-peer-urls"                              = "http://0.0.0.0:${var.peer_port}"
    "initial-cluster-token"                         = "${var.service_name}-cluster"
    "snapshot-count"                                = 1000
    "auto-compaction-mode"                          = "periodic"
    "auto-compaction-retention"                     = 1
    "data-dir"                                      = "${var.data_volume_mount_path}/default.etcd"
    "experimental-enable-distributed-tracing"       = true
    "experimental-distributed-tracing-address"      = var.otlp_receiver_endpoint
    "experimental-distributed-tracing-service-name" = var.service_name
  })
}

locals {
  config_map_name = kubernetes_config_map.config_map.metadata[0].name
  config_filename = var.config_filename
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = local.rendered
  }
}