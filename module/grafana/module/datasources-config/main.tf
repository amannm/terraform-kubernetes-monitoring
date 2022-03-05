locals {
  rendered = yamlencode({
    apiVersion = 1
    datasources = [
      {
        name      = "Prometheus"
        orgId     = 1
        version   = 1
        isDefault = true
        editable  = false
        type      = "prometheus"
        access    = "proxy"
        #uuid = ""
        url = var.prometheus_url
      },
      {
        name     = "Loki"
        orgId    = 1
        version  = 1
        editable = false
        type     = "loki"
        access   = "proxy"
        #uuid = ""
        url = var.loki_url
      },
      {
        name     = "Tempo"
        orgId    = 1
        version  = 1
        editable = false
        type     = "tempo"
        access   = "proxy"
        #uuid = ""
        url = var.tempo_url
      },
    ]
  })
}

locals {
  config_map_name = kubernetes_config_map.config_map.metadata[0].name
  config_filename = var.config_filename
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.config_map_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = local.rendered
  }
}