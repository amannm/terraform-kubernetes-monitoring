locals {
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
      active_query_tracker_dir = "${var.storage_path}/active-query-tracker"
      query_timeout            = "10s"
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
      max_chunk_age        = "5m"
      max_chunk_idle_time  = "30m"
      flush_period         = "1m"
      max_transfer_retries = 0
      lifecycler = {
        ring = {
          kvstore            = local.etcd_kvstore
          heartbeat_timeout  = "1m"
          replication_factor = 1
        }
      }
    }
    storage = {
      trace = {
        backend        = "local"
        blocklist_poll = "5m"
        local = {
          path = "${var.storage_path}/traces"
        }
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
      }
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