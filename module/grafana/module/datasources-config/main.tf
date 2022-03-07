locals {
  rendered = yamlencode({
    apiVersion = 1
    datasources = [
      {
        name      = "Prometheus"
        type      = "prometheus"
        uuid      = "prometheus"
        orgId     = 1
        version   = 1
        editable  = true
        access    = "proxy"
        url       = var.prometheus_url
        isDefault = true
      },
      {
        name     = "Loki"
        type     = "loki"
        uuid     = "loki"
        orgId    = 1
        version  = 1
        editable = true
        access   = "proxy"
        url      = var.loki_url
        jsonData = {
          derivedFields = [
            {
              datasourceUid : "tempo"
              matcherRegex = "(?:traceId|tid)=(\\w+)"
              name         = "TraceID"
              url          = "$${__value.raw}"
            },
          ]
        }
      },
      {
        name     = "Tempo"
        type     = "tempo"
        uuid     = "tempo"
        orgId    = 1
        version  = 1
        editable = true
        access   = "proxy"
        url      = var.tempo_url
        jsonData = {
          httpMethod = "GET"
          tracesToLogs = {
            lokiSearch         = true
            datasourceUid      = "loki"
            mapTagNamesEnabled = true
            mappedTags = [
              {
                key   = "service.name"
                value = "app_kubernetes_io_name"
              },
            ]
            #            spanStartTimeShift: "-1s"
            #            spanEndTimeShift: "1s"
          }
          serviceMap = {
            datasourceUid = "prometheus"
          }
          search = {
            hide = false
          }
          nodeGraph = {
            enabled = true
          }
        }
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