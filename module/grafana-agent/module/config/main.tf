locals {
  etcd_kvstore = {
    store = "etcd"
    etcd = {
      endpoints = [var.etcd_endpoint]
    }
  }
}

locals {
  rendered = yamlencode({
    server = {
      http_listen_port = var.agent_container_port
      log_level        = "info"
    }
    metrics = {
      global = {
        scrape_interval = "1m"
      }
      scraping_service = {
        enabled                       = true
        dangerous_allow_reading_files = true
        kvstore                       = local.etcd_kvstore
        lifecycler = {
          ring = {
            kvstore = local.etcd_kvstore
          }
        }
      }
      configs = []
    }
    logs = {
      positions_directory = var.positions_volume_mount_path
      configs = [
        {
          name = "default"
          clients = [
            {
              url = var.loki_remote_write_url
            }
          ]
          scrape_configs = [
            {
              job_name = "kubernetes-pods"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                },
              ]
              pipeline_stages = [
                {
                  docker = {}
                },
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_node_name"]
                  target_label  = "__host__"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_container_name"]
                  action        = "drop"
                  regex         = ""
                },
                {
                  action = "labelmap"
                  regex  = "__meta_kubernetes_pod_label_(.+)"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
                  action        = "replace"
                  separator     = "/"
                  target_label  = "job"
                  replacement   = "$1"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace"]
                  action        = "replace"
                  target_label  = "namespace"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_name"]
                  action        = "replace"
                  target_label  = "pod"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_container_name"]
                  action        = "replace"
                  target_label  = "container"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
                  target_label  = "__path__"
                  separator     = "/"
                  replacement   = "/var/log/pods/*$1/*.log"
                },
              ]
            }
          ]
        }
      ]
    }
    integrations = {
      metrics = {
        autoscrape = {
          enable = false
        }
      }
      node_exporter = {
        rootfs_path = var.host_root_volume_mount_path
        sysfs_path  = var.host_sys_volume_mount_path
        procfs_path = var.host_proc_volume_mount_path
      }
    }
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
