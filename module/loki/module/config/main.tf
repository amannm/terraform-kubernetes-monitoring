locals {
  worker_parallelism = 10
  etcd_kvstore = {
    store = "etcd"
    etcd = {
      endpoints = [var.etcd_host]
    }
  }
  fifo_cache = {
    for i in range(32) : i => {
      enable_fifocache = true
      fifocache = {
        max_size_bytes = pow(2, i)
        validity       = "24h"
      }
    }
  }
}

locals {
  rendered = yamlencode({
    auth_enabled = false
    server = {
      http_listen_port = var.http_port
      grpc_listen_port = var.grpc_port
      log_level        = "info"
    }
    frontend = {
      scheduler_address            = var.query_scheduler_hostname
      max_outstanding_per_tenant   = 100
      scheduler_worker_concurrency = 1
      compress_responses           = true
      log_queries_longer_than      = "5s"
      tail_proxy_url               = "http://${var.querier_hostname}:${var.http_port}"
    }
    query_range = {
      align_queries_with_step = true
      split_queries_by_interval : "15m"
      max_retries   = 5
      cache_results = true
      results_cache = {
        cache = local.fifo_cache["10"]
      }
    }
    query_scheduler = {
      max_outstanding_requests_per_tenant = 100
      use_scheduler_ring                  = true
      scheduler_ring = {
        kvstore = local.etcd_kvstore
      }
    }
    frontend_worker = {
      parallelism       = local.worker_parallelism
      scheduler_address = var.query_scheduler_hostname
    }
    querier = {
      query_timeout  = "1m"
      max_concurrent = local.worker_parallelism * var.max_query_frontend_replicas + local.worker_parallelism
      engine = {
        timeout = "3m"
      }
    }
    limits_config = {
      enforce_metric_name           = false
      ingestion_rate_strategy       = "global"
      ingestion_rate_mb             = 4
      retention_period              = "24h"
      max_cache_freshness_per_query = "10m"
      reject_old_samples            = true
      reject_old_samples_max_age    = "24h"
    }
    distributor = {
      ring = {
        kvstore = local.etcd_kvstore
      }
    }
    ingester = {
      chunk_block_size     = pow(2, 18)
      chunk_target_size    = pow(2, 18) * 6
      chunk_encoding       = "snappy"
      chunk_idle_period    = "30m"
      chunk_retain_period  = "1m"
      max_transfer_retries = 0
      lifecycler = {
        join_after : "5s"
        ring = {
          kvstore            = local.etcd_kvstore
          replication_factor = 1
        }
      }
      wal = {
        dir = "${var.storage_path}/wal"
      }
    }
    schema_config = {
      configs = [
        {
          from   = "1970-01-01"
          schema = "v11"
          store  = "boltdb-shipper"
          index = {
            prefix = "index_"
            period = "24h"
          }
          object_store = "filesystem"
          chunks = {
            prefix = "chunks_"
            period = "24h"
          }
        }
      ]
    }
    table_manager = {
      retention_deletes_enabled = true
      retention_period          = "0s"
    }
    storage_config = {
      index_queries_cache_config = local.fifo_cache["25"]
      boltdb_shipper = {
        shared_store           = "filesystem"
        active_index_directory = "${var.storage_path}/index"
        cache_location         = "${var.storage_path}/cache"
        cache_ttl              = "24h"
      }
      filesystem = {
        directory = "${var.storage_path}/chunks"
      }
    }
    chunk_store_config = {
      max_look_back_period = "0s"
      chunk_cache_config   = local.fifo_cache["26"]
    }
    compactor = {
      shared_store               = "filesystem"
      working_directory          = "${var.storage_path}/compactor"
      shared_store_key_prefix    = "index/"
      max_compaction_parallelism = 1
      compaction_interval        = "10m"
      compactor_ring = {
        kvstore = local.etcd_kvstore
      }
    }
    tracing = {
      enabled = true
    }
  })
}

locals {
  config_map_name    = kubernetes_config_map.config_map.metadata[0].name
  config_filename    = var.config_filename
  storage_mount_path = var.storage_path
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