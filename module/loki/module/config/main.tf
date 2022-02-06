locals {
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
      }
    }
  }
}

locals {
  rendered = yamlencode({
    target = join(",", [

      //"all",
      //"read",
      //"write",

      "distributor",
      "ingester",
      "ingester-querier",

      "query-frontend",
      "query-scheduler",
      "querier",

      //"ruler",

      "table-manager",
      "index-gateway",
      "compactor",

    ])

    auth_enabled = false
    server = {
      http_listen_port = var.http_port
      log_level        = "info"
    }

    // query
    frontend = {
      max_outstanding_per_tenant   = 10
      scheduler_worker_concurrency = 1
      compress_responses           = true
    }
    query_range = {
      cache_results = true
      results_cache = {
        cache = local.fifo_cache["23"]
      }
    }
    query_scheduler = {
      max_outstanding_requests_per_tenant = 10
      use_scheduler_ring                  = true
      scheduler_ring = {
        kvstore = local.etcd_kvstore
      }
    }
    frontend_worker = {
      parallelism = 1
    }
    querier = {
      query_timeout  = "30s"
      max_concurrent = 1
      engine = {
        timeout = "3m"
      }
    }

    #ruler = {}

    // ingest
    limits_config = {
      ingestion_rate_strategy       = "global"
      ingestion_rate_mb             = 4
      retention_period              = "24h"
      max_cache_freshness_per_query = "10m"
    }
    distributor = {
      ring = {
        kvstore           = local.etcd_kvstore
        heartbeat_timeout = "1m"
      }
    }
    ingester = {
      chunk_block_size     = pow(2, 18)
      chunk_target_size    = pow(2, 18) * 6
      chunk_encoding       = "gzip"
      chunk_retain_period  = "1m"
      chunk_idle_period    = "3m"
      max_transfer_retries = 0
      lifecycler = {
        ring = {
          kvstore            = local.etcd_kvstore
          heartbeat_timeout  = "1m"
          replication_factor = 1
        }
        heartbeat_period = "5s"
      }
      wal = {
        enabled = true
        dir     = "${var.storage_path}/wal"
      }
    }
    ingester_client = {
      pool_config = {
        health_check_ingesters = true
        client_cleanup_period  = "15s"
        // TODO: docs seem wrong here
        // remotetimeout          = "30s"
      }
      remote_timeout = "5s"
    }

    // storage
    schema_config = {
      configs = [
        {
          from       = "1970-01-01"
          schema     = "v11"
          row_shards = 16
          store      = "boltdb-shipper"
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
      retention_period          = "24h"
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
      compaction_interval        = "5m"
      compactor_ring = {
        kvstore = local.etcd_kvstore
      }
    }

    // for tracing with Jaeger
    tracing = {
      enabled = true
    }

    // for tuning limits or multi KV settings during operation
    // runtime_config = {}

    // to avoid copy/paste
    // common = {}
  })
}