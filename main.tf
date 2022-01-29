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
  container_image = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
}

module "prometheus_server" {
  source                           = "./module/prometheus-server"
  namespace_name                   = var.namespace_name
  service_name                     = "prometheus-server"
  service_port                     = var.prometheus_server_port
  server_container_image           = "quay.io/prometheus/prometheus:v2.31.1"
  configmap_reload_container_image = "jimmidyson/configmap-reload:v0.5.0"
}

module "prometheus_node_exporter" {
  source          = "./module/prometheus-node-exporter"
  namespace_name  = var.namespace_name
  service_name    = "prometheus-node-exporter"
  service_port    = var.prometheus_node_exporter_port
  container_image = "quay.io/prometheus/node-exporter:v1.3.0"
}

module "grafana" {
  source          = "./module/grafana"
  namespace_name  = var.namespace_name
  service_name    = "grafana"
  service_port    = var.grafana_port
  container_image = "grafana/grafana:8.3.4"
}