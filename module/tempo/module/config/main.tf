terraform {
  experiments = [
    module_variable_optional_attrs
  ]
}
locals {
  store_type = contains(keys(var.storage_config), "local") ? "filesystem" : contains(keys(var.storage_config), "gcp") ? "gcs" : null

  etcd_kvstore = {
    store  = "etcd"
    prefix = "${var.service_name}/collectors/"
    etcd = {
      endpoints = [var.etcd_host]
    }
  }
}
locals {
  rendered = yamlencode({
    multitenancy_enabled = false
    search_enabled       = false
    server = {
      http_listen_port          = var.http_port
      grpc_listen_port          = var.grpc_port
      log_level                 = "debug"
      graceful_shutdown_timeout = "30s"
    }
    query_frontend = {
      search = {
        concurrent_jobs = 50
      }
    }
    querier = {
      query_timeout = "10s"
      frontend_worker = {
        frontend_address = "${var.query_frontend_hostname}:${var.grpc_port}"
      }
    }
    distributor = {
      receivers = {
        jaeger = {
          protocols = {
            grpc = {}
          }
        }
      }
      log_received_traces : true
    }
    ingester = {
      lifecycler = {
        ring = {
          kvstore            = local.etcd_kvstore
          heartbeat_timeout  = "1m"
          replication_factor = 1
        }
      }
    }
    storage = {
      trace = merge({
        backend        = "local"
        blocklist_poll = "5m"
        pool = {
          max_workers = 30
          queue_depth = 10000
        }
        wal = {
          path            = "${var.storage_path}/wal"
          encoding        = "snappy"
          search_encoding = "snappy"
        }
        block = {
          encoding        = "snappy"
          search_encoding = "snappy"
        }
        }, contains(keys(var.storage_config), "gcp") ? {
        gcs = {
          bucket_name = var.storage_config.gcp.bucket_name
        }
        } : contains(keys(var.storage_config), "local") ? {
        local = {
          path = "${var.storage_path}/traces"
        }
      } : {})
    }
    compactor = {
      ring = {
        kvstore           = local.etcd_kvstore
        heartbeat_timeout = "1m"
      }
      compaction = {
        retention_concurrency = 10
        compaction_window     = "1h"
        block_retention       = "24h"
      }
    }
  })
}

locals {
  config_map_name    = kubernetes_config_map.config_map.metadata[0].name
  config_filename    = var.config_filename
  storage_mount_path = var.storage_path
  config_mount_path  = var.config_path
  http_port          = var.http_port
  grpc_port          = var.grpc_port
  etcd_host          = var.etcd_host
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