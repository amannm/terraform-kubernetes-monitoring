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
  source         = "./module/kube-state-metrics"
  namespace_name = kubernetes_namespace.namespace.metadata[0].name
  port           = var.kube_state_metrics_port
}

module "prometheus_server" {
  source                          = "./module/prometheus-server"
  namespace_name                  = kubernetes_namespace.namespace.metadata[0].name
  port                            = var.prometheus_server_port
  kube_state_metrics_service_name = module.kube_state_metrics.service_name
  kube_state_metrics_service_port = module.kube_state_metrics.service_port
}

module "prometheus_node_exporter" {
  source         = "./module/prometheus-node-exporter"
  namespace_name = kubernetes_namespace.namespace.metadata[0].name
  port           = var.prometheus_node_exporter_port
}

module "grafana" {
  source         = "./module/grafana"
  namespace_name = kubernetes_namespace.namespace.metadata[0].name
  port           = var.grafana_port
}