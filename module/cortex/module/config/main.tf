locals {
  store_type = var.storage_config["local"] != null ? "filesystem" : var.storage_config["gcp"] != null ? "gcs" : null

  worker_parallelism = 10
  #  etcd_kvstore = {
  #    store  = "etcd"
  #    prefix = "${var.service_name}/collectors/"
  #    etcd = {
  #      endpoints = [var.etcd_host]
  #    }
  #  }
  memberlist_kvstore = {
    store = "memberlist"
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
    api = {
      prometheus_http_prefix       = var.prometheus_api_path
      response_compression_enabled = true
    }
    memberlist = {
      randomize_node_name = false
      gossip_nodes        = 3
      join_members        = var.gossip_hostnames
      bind_port           = var.gossip_port
    }
    frontend = {
      max_outstanding_per_tenant   = 100
      scheduler_worker_concurrency = 1
      log_queries_longer_than      = "5s"
      #scheduler_address            = "${var.query_scheduler_hostname}:${var.grpc_port}"
    }

    #    query_scheduler = {
    #      max_outstanding_requests_per_tenant = 100
    #    }
    frontend_worker = {
      match_max_concurrent = true
      #scheduler_address = "${var.query_scheduler_hostname}:${var.grpc_port}"
      frontend_address = "${var.query_frontend_hostname}:${var.grpc_port}"
    }
    querier = {
      active_query_tracker_dir = "${var.storage_path}/active-query-tracker"
      timeout                  = "1m"
      max_concurrent           = local.worker_parallelism * var.max_query_frontend_replicas + local.worker_parallelism
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
    limits = {
      max_label_names_per_series        = 50
      enforce_metric_name               = false
      ingestion_rate_strategy           = "global"
      compactor_blocks_retention_period = "24h"
      max_cache_freshness               = "10m"
      reject_old_samples                = true
      reject_old_samples_max_age        = "24h"
    }
    distributor = {
      pool = {
        health_check_ingesters = true
        client_cleanup_period  = "15s"
      }
      shard_by_all_labels = false
      remote_timeout      = "5s"
      ring = {
        kvstore           = local.memberlist_kvstore
        heartbeat_period  = "5s"
        heartbeat_timeout = "1m"
      }
    }
    ingester = {
      max_stale_chunk_idle_time = 0
      max_chunk_idle_time       = "1m"
      max_chunk_age             = "2m"
      retain_period             = "1m"
      flush_period              = "1m"
      max_transfer_retries      = 0
      lifecycler = {
        ring = {
          kvstore            = local.memberlist_kvstore
          heartbeat_timeout  = "1m"
          replication_factor = 1
        }
        join_after             = "30s"
        heartbeat_period       = "5s"
        min_ready_duration     = "15s"
        final_sleep            = "30s"
        unregister_on_shutdown = true
        #        readiness_check_ring_health = false
      }
    }
    storage = {
      engine = "blocks"
    }
    blocks_storage = merge({
      backend = local.store_type
      tsdb = {
        dir                                 = "${var.storage_path}/tsdb"
        block_ranges_period                 = ["1h"]
        retention_period                    = "2h"
        ship_interval                       = "1m"
        head_compaction_interval            = "1m"
        head_compaction_idle_timeout        = "30m"
        head_chunks_write_buffer_size_bytes = 4194304
        stripe_size                         = pow(2, 12)
        wal_compression_enabled             = false
        wal_segment_size_bytes              = 134217728
        flush_blocks_on_shutdown            = true
      }
      bucket_store = {
        sync_dir = "${var.storage_path}/tsdb-sync"
        index_cache = {
          backend = "inmemory"
          inmemory = {
            max_size_bytes = pow(2, 26)
          }
        }
        bucket_index = {
          enabled = true
        }
      }
      }, var.storage_config["gcp"] != null ? {
      gcs = {
        bucket_name = var.storage_config.gcp.bucket_name
      }
      } : var.storage_config["local"] != null ? {
      filesystem = {
        dir = "${var.storage_path}/blocks"
      }
    } : {})
    compactor = {
      data_dir               = "${var.storage_path}/compactor"
      compaction_concurrency = 1
      compaction_interval    = "1h"
      cleanup_interval       = "15m"
      sharding_enabled       = true
      sharding_ring = {
        kvstore                      = local.memberlist_kvstore
        heartbeat_period             = "5s"
        heartbeat_timeout            = "1m"
        wait_stability_min_duration  = "1s"
        wait_stability_max_duration  = "5s"
        wait_active_instance_timeout = "5s"
      }
    }
    store_gateway = {
      sharding_enabled = true
      sharding_ring = {
        kvstore                     = local.memberlist_kvstore
        heartbeat_period            = "15s"
        heartbeat_timeout           = "1m"
        wait_stability_min_duration = "1s"
        wait_stability_max_duration = "5s"
        replication_factor          = 1
      }
    }
  })
}

locals {
  config_map_name    = kubernetes_config_map.config_map.metadata[0].name
  config_filename    = var.config_filename
  storage_mount_path = var.storage_path
  config_mount_path  = var.config_path
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