locals {

  kubernetes_sd_config = { for v in ["endpoints", "pod", "service", "node"] : v => [{ role = v }] }

  kubernetes_sd_name_label_rename = {
    for k, v in {
      namespace     = "__meta_kubernetes_namespace"
      endpoint_node = "__meta_kubernetes_endpoint_node_name"
      pod_node      = "__meta_kubernetes_pod_node_name"
      service       = "__meta_kubernetes_service_name"
      pod           = "__meta_kubernetes_pod_name"
      ingress       = "__meta_kubernetes_ingress_name"
      } : k => {
      source_labels = [v]
      target_label  = k
    }
  }

  kubernetes_sd_label_remap = {
    for v in ["service", "node", "pod", "ingress"] : v =>
    {
      action = "labelmap"
      regex  = "__meta_kubernetes_${v}_label_(.+)"
    }
  }

  kubernetes_sd_node_jobs = {
    for v in ["/metrics", "/metrics/cadvisor"] : v => {
      job_name              = "kubernetes-nodes${replace(v, "/", "-")}"
      scheme                = "https"
      bearer_token_file     = local.auth_token_path
      tls_config            = local.auth_tls_config
      kubernetes_sd_configs = local.kubernetes_sd_config["node"]
      relabel_configs = [
        local.kubernetes_sd_label_remap["node"],
        {
          replacement  = "kubernetes.default.svc:443"
          target_label = "__address__"
        },
        {
          source_labels = ["__meta_kubernetes_node_name"]
          regex         = "(.+)"
          replacement   = "/api/v1/nodes/$1/proxy${v}"
          target_label  = "__metrics_path__"
        },
      ]
    }
  }
}

locals {
  auth_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  auth_tls_config = {
    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    insecure_skip_verify = true
  }
}

locals {

  # monitor Node metrics
  node_job = local.kubernetes_sd_node_jobs["/metrics"]

  # monitor Node cAdvisor metrics
  node_cadvisor_job = local.kubernetes_sd_node_jobs["/metrics/cadvisor"]

  # monitor Kubernetes API endpoints
  api_service_endpoint_job = {
    job_name              = "kubernetes-api-endpoints"
    scheme                = "https"
    metrics_path          = "/metrics"
    bearer_token_file     = local.auth_token_path
    tls_config            = local.auth_tls_config
    kubernetes_sd_configs = local.kubernetes_sd_config["endpoints"]
    relabel_configs = [
      {
        action = "keep"
        source_labels = [
          "__meta_kubernetes_service_name",
          "__meta_kubernetes_namespace",
          "__meta_kubernetes_endpoint_port_name",
        ]
        regex = "kubernetes;default;https"
      },
    ]
  }

  # for each service endpoint, check at http://<ip:port>/metrics and associate any kubernetes labels with them
  service_endpoints_job = {
    job_name              = "kubernetes-service-endpoints"
    scheme                = "http"
    metrics_path          = "/metrics"
    kubernetes_sd_configs = local.kubernetes_sd_config["endpoints"]
    relabel_configs = [
      local.kubernetes_sd_label_remap["service"],
      local.kubernetes_sd_name_label_rename["namespace"],
      local.kubernetes_sd_name_label_rename["service"],
    ]
  }

  # for each active pod, check at http://<ip:port>/metrics and associate any kubernetes labels with them
  pods_job = {
    job_name              = "kubernetes-pods"
    scheme                = "http"
    metrics_path          = "/metrics"
    kubernetes_sd_configs = local.kubernetes_sd_config["pod"]
    relabel_configs = [
      {
        action        = "drop"
        source_labels = ["__meta_kubernetes_pod_phase"]
        regex         = "Pending|Succeeded|Failed|Completed"
      },
      local.kubernetes_sd_label_remap["pod"],
      local.kubernetes_sd_name_label_rename["namespace"],
      local.kubernetes_sd_name_label_rename["pod_node"],
      local.kubernetes_sd_name_label_rename["pod"],
    ]
  }

  etcd_kvstore = {
    store = "etcd"
    etcd = {
      endpoints = [var.etcd_endpoint]
    }
  }
}

locals {
  scrape_rendered = yamlencode({
    scrape_configs = [
      local.node_job,
      local.node_cadvisor_job,
      local.api_service_endpoint_job,
      local.service_endpoints_job,
      local.pods_job,
    ]
    remote_write = [
      {
        url = var.metrics_remote_write_url
      }
    ]
  })
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
            replication_factor : 2
          }
        }
      }
      configs : []
    }
    logs = {
      positions_directory = var.positions_volume_mount_path
      configs = [
        {
          name = "default"
          clients = [
            {
              url = "http://${var.loki_api_host}/loki/api/v1/push"
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