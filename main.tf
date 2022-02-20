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

module "shared_etcd" {
  source              = "./module/etcd"
  namespace_name      = var.namespace_name
  service_name        = "etcd"
  container_image     = "quay.io/coreos/etcd:v3.5.2"
  cluster_size        = 2
  storage_volume_size = 1
}

module "kube_state_metrics" {
  source          = "./module/kube-state-metrics"
  namespace_name  = kubernetes_namespace.namespace.metadata[0].name
  service_name    = "kube-state-metrics"
  service_port    = var.kube_state_metrics_port
  container_image = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
}

module "grafana_agent" {
  source                   = "./module/grafana-agent"
  namespace_name           = kubernetes_namespace.namespace.metadata[0].name
  resource_name            = "grafana-agent"
  agent_container_image    = "grafana/agent:latest"
  etcd_host                = module.shared_etcd.client_endpoint_host
  metrics_remote_write_url = module.cortex.remote_write_url
  loki_remote_write_url    = module.loki.remote_write_url
}

#module "prometheus_server" {
#  source                 = "./module/prometheus-server"
#  namespace_name         = kubernetes_namespace.namespace.metadata[0].name
#  service_name           = "prometheus-server"
#  service_port           = var.prometheus_server_port
#  storage_volume_size    = 4
#  storage_retention_days = 1
#  server_container_image = "quay.io/prometheus/prometheus:latest"
#}

module "grafana" {
  source          = "./module/grafana"
  namespace_name  = kubernetes_namespace.namespace.metadata[0].name
  service_name    = "grafana"
  service_port    = var.grafana_port
  container_image = "grafana/grafana:latest"
}

module "loki" {
  source              = "./module/loki"
  namespace_name      = kubernetes_namespace.namespace.metadata[0].name
  service_name        = "loki"
  service_port        = var.loki_port
  container_image     = "grafana/loki:2.4.2"
  storage_volume_size = 2
  etcd_host           = module.shared_etcd.client_endpoint_host
}

module "cortex" {
  source              = "./module/cortex"
  namespace_name      = kubernetes_namespace.namespace.metadata[0].name
  service_name        = "cortex"
  service_port        = var.cortex_port
  container_image     = "quay.io/cortexproject/cortex:v1.11.0"
  storage_volume_size = 2
  etcd_host           = module.shared_etcd.client_endpoint_host
}