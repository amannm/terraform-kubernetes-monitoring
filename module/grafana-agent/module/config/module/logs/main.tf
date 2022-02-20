locals {
  logs_config = {
    positions_directory = var.positions_volume_mount_path
    configs = [
      {
        name = "default"
        clients = [
          {
            url = var.remote_write_url
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
}
