locals {

  node_metrics_labels = {
    for v in ["/metrics", "/metrics/cadvisor"] : v => [
      {
        action = "labelmap"
        regex  = "__meta_kubernetes_node_label_(.+)"
      },
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

  name_labels = {
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

  scraped_labels = {
    for v in ["service", "node", "pod", "ingress"] : v => [
      {
        action        = "keep"
        source_labels = ["__meta_kubernetes_${v}_annotation_prometheus_io_scrape"]
        regex         = "true"
      },
      {
        source_labels = ["__meta_kubernetes_${v}_annotation_prometheus_io_scheme"]
        regex         = "(https?)"
        target_label  = "__scheme__"
      },
      {
        source_labels = ["__meta_kubernetes_${v}_annotation_prometheus_io_path"]
        regex         = "(.+)"
        target_label  = "__metrics_path__"
      },
      {
        source_labels = [
          "__address__",
          "__meta_kubernetes_${v}_annotation_prometheus_io_port",
        ]
        regex        = "([^:]+)(?::\\d+)?;(\\d+)"
        replacement  = "$1:$2"
        target_label = "__address__"
      },
      {
        action      = "labelmap"
        regex       = "__meta_kubernetes_${v}_annotation_prometheus_io_param_(.+)"
        replacement = "__param_$1"
      },
      {
        action = "labelmap"
        regex  = "__meta_kubernetes_${v}_label_(.+)"
      }
    ]
  }
  sd_config = { for v in ["endpoints", "pod", "service", "node"] : v => [{ role = v }] }

}

locals {
  auth_token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  auth_scheme     = "https"
  auth_tls_config = {
    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    insecure_skip_verify = true
  }
}

locals {

  self_job = {
    job_name = "prometheus"
    static_configs = [
      {
        targets = [
          "localhost:${var.port}"
        ]
      }
    ]
  }

  kube_state_metrics_job = {
    job_name = "kube-state-metrics"
    static_configs = [
      {
        targets = [
          "${var.kube_state_metrics_service_name}.${var.namespace_name}.svc.cluster.localhost:${var.kube_state_metrics_service_port}"
        ]
      }
    ]
  }

  api_server_job = {
    job_name              = "kubernetes-apiservers"
    kubernetes_sd_configs = local.sd_config["endpoints"]
    relabel_configs = [
      {
        action = "keep"
        source_labels = [
          "__meta_kubernetes_namespace",
          "__meta_kubernetes_service_name",
          "__meta_kubernetes_endpoint_port_name",
        ]
        regex = "default;kubernetes;https"
      },
    ]
    bearer_token_file = local.auth_token_path
    scheme            = local.auth_scheme
    tls_config        = local.auth_tls_config
  }

  node_job = {
    job_name              = "kubernetes-nodes"
    kubernetes_sd_configs = local.sd_config["node"]
    relabel_configs       = local.node_metrics_labels["/metrics"]
    bearer_token_file     = local.auth_token_path
    scheme                = local.auth_scheme
    tls_config            = local.auth_tls_config
  }

  node_cadvisor_job = {
    job_name              = "kubernetes-nodes-cadvisor"
    kubernetes_sd_configs = local.sd_config["node"]
    relabel_configs       = local.node_metrics_labels["/metrics/cadvisor"]
    bearer_token_file     = local.auth_token_path
    scheme                = local.auth_scheme
    tls_config            = local.auth_tls_config
  }

  pods_job = {
    job_name              = "kubernetes-pods"
    kubernetes_sd_configs = local.sd_config["pod"]
    relabel_configs = concat(
      local.scraped_labels["pod"],
      [
        {
          action        = "drop"
          source_labels = ["__meta_kubernetes_pod_phase"]
          regex         = "Pending|Succeeded|Failed|Completed"
        },
        local.name_labels["namespace"],
        local.name_labels["pod_node"],
        local.name_labels["pod"],
      ]
    )
  }

  endpoints_job = {
    job_name              = "kubernetes-service-endpoints"
    kubernetes_sd_configs = local.sd_config["endpoints"]
    relabel_configs = concat(
      local.scraped_labels["service"],
      [
        local.name_labels["namespace"],
        local.name_labels["service"],
      ]
    )
  }
}

locals {
  rendered = yamlencode({
    global = {
      scrape_interval     = "1m"
      scrape_timeout      = "10s"
      evaluation_interval = "1m"
    }
    rule_files = [
      "/etc/config/recording_rules.yml",
      "/etc/config/alerting_rules.yml",
    ]
    scrape_configs = [
      local.self_job,
      local.kube_state_metrics_job,
      local.api_server_job,
      local.node_job,
      local.node_cadvisor_job,
      local.pods_job,
      local.endpoints_job,
    ]
  })
}


