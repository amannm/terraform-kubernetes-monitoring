locals {
  store_type = var.storage_config["local"] != null ? "local" : var.storage_config["gcp"] != null ? "gcs" : null

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
}
locals {
  rendered = yamlencode({
    multitenancy_enabled = false
    search_enabled       = false
    server = {
      http_listen_port          = var.http_port
      grpc_listen_port          = var.grpc_port
      log_level                 = "info"
      graceful_shutdown_timeout = "30s"
    }
    memberlist = {
      randomize_node_name = false
      gossip_nodes        = 3
      join_members        = var.gossip_hostnames
      bind_port           = var.gossip_port
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
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:${var.otlp_grpc_port}"
            }
          }
        }
      }
      log_received_traces : true
    }
    ingester = {
      lifecycler = {
        ring = {
          kvstore            = local.memberlist_kvstore
          heartbeat_timeout  = "1m"
          replication_factor = 1
        }
      }
    }
    storage = {
      trace = merge({
        backend        = local.store_type
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
        }, var.storage_config["gcp"] != null ? {
        gcs = {
          bucket_name = var.storage_config.gcp.bucket_name
        }
        } : var.storage_config["local"] != null ? {
        local = {
          path = "${var.storage_path}/traces"
        }
      } : {})
    }
    compactor = {
      ring = {
        kvstore           = local.memberlist_kvstore
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