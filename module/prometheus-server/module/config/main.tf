locals {
  config_filename = "prometheus.yml"
}

locals {
  rendered = yamlencode({
    global         = {}
    rule_files     = []
    scrape_configs = []
  })
}

locals {
  config_map_name = kubernetes_config_map.config_map.metadata[0].name
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.config_map_name
    namespace = var.namespace_name
  }
  data = {
    (var.config_filename) = local.rendered
  }
}