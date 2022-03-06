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

  prometheus_override_labels_relabel_configs = {
    for resource_type in ["service", "pod"] : resource_type =>
    [
      {
        source_labels : ["__meta_kubernetes_${resource_type}_annotation_prometheus_io_scrape"]
        action = "drop"
        regex  = "false"
      },
      {
        source_labels : ["__meta_kubernetes_${resource_type}_annotation_prometheus_io_scheme"]
        action       = "replace"
        target_label = "__scheme__"
        regex        = "(https?)"
      },
      {
        source_labels : ["__address__", "__meta_kubernetes_${resource_type}_annotation_prometheus_io_port"]
        action       = "replace"
        target_label = "__address__"
        regex        = "([^:]+)(?::\\d+)?;(\\d+)"
      },
      {
        source_labels = ["__meta_kubernetes_${resource_type}_annotation_prometheus_io_path"]
        action        = "replace"
        target_label  = "__metrics_path__"
        regex         = "(.+)"
      }
    ]
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
  jobs = concat(
    [
      local.kubernetes_sd_node_jobs["/metrics"],
      local.kubernetes_sd_node_jobs["/metrics/cadvisor"],
      {
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
      },
      {
        job_name              = "kubernetes-pods"
        scheme                = "http"
        metrics_path          = "/metrics"
        kubernetes_sd_configs = local.kubernetes_sd_config["pod"]
        relabel_configs = concat(
          [
            for label_name, label_value_list in var.partition_by_labels :
            {
              action        = "drop"
              source_labels = ["__meta_kubernetes_pod_label_${replace(label_name, "/[^a-zA-Z0-9_]/", "_")}"]
              regex         = join("|", label_value_list)
            }
          ],
          [
            {
              action        = "drop"
              source_labels = ["__meta_kubernetes_pod_phase"]
              regex         = "Pending|Succeeded|Failed|Completed"
            }
          ],
          local.prometheus_override_labels_relabel_configs["pod"],
          [
            local.kubernetes_sd_label_remap["pod"],
            local.kubernetes_sd_name_label_rename["namespace"],
            local.kubernetes_sd_name_label_rename["pod_node"],
            local.kubernetes_sd_name_label_rename["pod"],
          ]
        )
      }
    ],
    flatten([
      for label_name, label_value_list in var.partition_by_labels : [
        for label_value in label_value_list : {
          job_name              = "kubernetes-pods-${replace(label_name, "/[^a-zA-Z0-9_]/", "_")}-${label_value}"
          scheme                = "http"
          metrics_path          = "/metrics"
          kubernetes_sd_configs = local.kubernetes_sd_config["pod"]
          relabel_configs = concat(
            [
              {
                action        = "keep"
                source_labels = ["__meta_kubernetes_pod_label_${replace(label_name, "/[^a-zA-Z0-9_]/", "_")}"]
                regex         = label_value
              },
              {
                action        = "drop"
                source_labels = ["__meta_kubernetes_pod_phase"]
                regex         = "Pending|Succeeded|Failed|Completed"
              }
            ],
            local.prometheus_override_labels_relabel_configs["pod"],
            [
              local.kubernetes_sd_label_remap["pod"],
              local.kubernetes_sd_name_label_rename["namespace"],
              local.kubernetes_sd_name_label_rename["pod_node"],
              local.kubernetes_sd_name_label_rename["pod"],
            ]
          )
        }
      ]
    ]),
  )
}

locals {
  metrics_config = {
    global = {
      scrape_interval = "5m"
    }
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

// TODO: further partition pod and service endpoint jobs
locals {
  config_volume_name       = "config"
  config_volume_mount_path = "/etc/configs"
}
locals {
  service_name = "${var.app_name}-${var.component_name}"
  labels = {
    "app.kubernetes.io/name"      = var.app_name
    "app.kubernetes.io/component" = var.component_name
  }
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = local.service_name
    namespace = var.namespace_name
  }
  data = {
    for v in local.jobs : "${replace(v.job_name, "/[^a-zA-Z0-9_]/", "_")}.yaml" => yamlencode({
      scrape_configs = [v]
      remote_write = [
        {
          url = var.remote_write_url
        }
      ]
    })
  }
}
resource "kubernetes_cron_job" "config_update_job" {
  metadata {
    namespace = var.namespace_name
    name      = local.service_name
    labels    = local.labels
  }
  spec {
    schedule                      = "*/${var.refresh_rate} * * * *"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    job_template {
      metadata {
        name   = local.service_name
        labels = local.labels
      }
      spec {
        ttl_seconds_after_finished = 30
        template {
          metadata {
            name   = local.service_name
            labels = local.labels
          }
          spec {
            dynamic "affinity" {
              for_each = var.stateless_node_labels
              content {
                node_affinity {
                  preferred_during_scheduling_ignored_during_execution {
                    weight = 100
                    preference {
                      match_expressions {
                        key      = affinity.key
                        operator = "In"
                        values   = affinity.value
                      }
                    }
                  }
                }
              }
            }
            restart_policy          = "OnFailure"
            active_deadline_seconds = 15
            volume {
              name = local.config_volume_name
              config_map {
                name = kubernetes_config_map.config_map.metadata[0].name
              }
            }
            container {
              name              = local.service_name
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
