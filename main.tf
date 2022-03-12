terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

module "grafana" {
  source                = "./module/grafana"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "grafana"
  service_port          = var.grafana_port
  container_image       = "grafana/grafana:latest"
  stateless_node_labels = var.stateless_node_labels
  container_port        = var.grafana_port
  storage_volume_size   = 1
  prometheus_url        = module.cortex.prometheus_url
  loki_url              = module.loki.loki_url
  tempo_url             = module.tempo.tempo_url
}

module "etcd" {
  source                = "./module/etcd"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "etcd"
  service_port          = var.etcd_port
  container_image       = "quay.io/coreos/etcd:v3.5.2"
  stateless_node_labels = var.stateless_node_labels
  storage_volume_size   = 1
  cluster_size          = 1
}

module "kube_state_metrics" {
  source                = "./module/kube-state-metrics"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "kube-state-metrics"
  service_port          = var.kube_state_metrics_port
  container_image       = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
  stateless_node_labels = var.stateless_node_labels
}

module "grafana_agent" {
  source                   = "./module/grafana-agent"
  cluster_domain           = var.cluster_domain
  namespace_name           = var.namespace_name
  service_name             = "grafana-agent"
  service_port             = var.grafana_agent_port
  jaeger_receiver_port     = var.jaeger_receiver_port
  zipkin_receiver_port     = var.zipkin_receiver_port
  agent_container_image    = "grafana/agent:latest"
  agentctl_container_image = "grafana/agentctl:latest"
  stateless_node_labels    = var.stateless_node_labels
  etcd_host                = module.etcd.client_endpoint_host
  metrics_remote_write_url = module.cortex.remote_write_url
  partition_by_labels = {
    "app.kubernetes.io/name" = ["grafana", "etcd", "kube-state-metrics", "grafana-agent", "cortex", "loki"]
  }
  logs_remote_write_url        = module.loki.remote_write_url
  traces_remote_write_endpoint = module.tempo.remote_write_endpoint
}

module "cortex" {
  source                = "./module/cortex"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "cortex"
  service_port          = var.cortex_port
  service_account       = var.cortex_service_account
  container_image       = "quay.io/cortexproject/cortex:v1.11.0"
  stateless_node_labels = var.stateless_node_labels
  storage_volume_size   = 1
  storage_config        = var.cortex_storage_config
}

module "loki" {
  source                = "./module/loki"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "loki"
  service_port          = var.loki_port
  service_account       = var.loki_service_account
  container_image       = "grafana/loki:2.4.2"
  stateless_node_labels = var.stateless_node_labels
  storage_volume_size   = 1
  etcd_host             = module.etcd.client_endpoint_host
  storage_config        = var.loki_storage_config
}

module "tempo" {
  source                = "./module/tempo"
  cluster_domain        = var.cluster_domain
  namespace_name        = var.namespace_name
  service_name          = "tempo"
  service_port          = var.tempo_port
  otlp_grpc_port        = 4317
  service_account       = var.tempo_service_account
  container_image       = "grafana/tempo:1.3.2"
  stateless_node_labels = var.stateless_node_labels
  storage_volume_size   = 1
  etcd_host             = module.etcd.client_endpoint_host
  storage_config        = var.tempo_storage_config
}