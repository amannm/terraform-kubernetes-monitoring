terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.namespace_name
  }
}

module "kube_state_metrics" {
  source          = "./module/kube-state-metrics"
  namespace_name  = var.namespace_name
  service_name    = "kube-state-metrics"
  service_port    = var.kube_state_metrics_port
  container_image = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:latest"
}

module "grafana_agent" {
  source                   = "./module/grafana-agent"
  namespace_name           = var.namespace_name
  resource_name            = "grafana-agent"
  container_image          = "grafana/agent:latest"
  metrics_remote_write_url = "http://${module.prometheus_server.service_name}.${var.namespace_name}.svc.cluster.local:${module.prometheus_server.service_port}/api/v1/write"
}

module "prometheus_server" {
  source                           = "./module/prometheus-server"
  namespace_name                   = var.namespace_name
  service_name                     = "prometheus-server"
  service_port                     = var.prometheus_server_port
  server_container_image           = "quay.io/prometheus/prometheus:latest"
  configmap_reload_container_image = "jimmidyson/configmap-reload:latest"
}

module "grafana" {
  source          = "./module/grafana"
  namespace_name  = var.namespace_name
  service_name    = "grafana"
  service_port    = var.grafana_port
  container_image = "grafana/grafana:latest"
}