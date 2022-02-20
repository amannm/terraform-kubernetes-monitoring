# helpers
locals {
  etcd_kvstore = {
    store = "etcd"
    etcd = {
      endpoints = [var.etcd_host]
    }
  }

  auth_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  auth_tls_config = {
    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    insecure_skip_verify = true
  }

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

# scrape jobs
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
}

locals {
  metrics_config = {
    scraping_service = {
      enabled                       = true
      dangerous_allow_reading_files = true
      kvstore                       = local.etcd_kvstore
      lifecycler = {
        ring = {
          kvstore           = local.etcd_kvstore
          heartbeat_timeout = "1m"
        }
        join_after         = "0s"
        heartbeat_period   = "5s"
        min_ready_duration = "1m"
        final_sleep        = "30s"
      }
    }
    configs = []
  }
  integrations_metrics_config = {
    autoscrape = {
      enable = false
    }
  }
}

locals {
  config_filename          = "agent.yaml"
  config_volume_name       = "config"
  config_volume_mount_path = "/etc/configs"
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.resource_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = yamlencode({
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
  }
}
resource "kubernetes_cron_job" "config_update_job" {
  metadata {
    namespace = var.namespace_name
    name      = var.resource_name
  }
  spec {
    schedule                      = "*/${var.refresh_rate} * * * *"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    job_template {
      metadata {
        name = var.resource_name
      }
      spec {
        ttl_seconds_after_finished = "120"
        template {
          metadata {
            name = var.resource_name
          }
          spec {
            restart_policy          = "OnFailure"
            active_deadline_seconds = 600
            volume {
              name = local.config_volume_name
              config_map {
                name = kubernetes_config_map.config_map.metadata[0].name
              }
            }
            container {
              name              = var.resource_name
              image             = var.agentctl_container_image
              image_pull_policy = "IfNotPresent"
              command           = ["/bin/agentctl"]
              args = [
                "config-sync",
                local.config_volume_mount_path,
                "--addr",
                "http://${var.agent_host}",
              ]
              volume_mount {
                name       = local.config_volume_name
                mount_path = local.config_volume_mount_path
              }
            }
          }
        }
      }
    }
  }
}
