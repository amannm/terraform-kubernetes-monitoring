terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
locals {
  partition_by_labels = {
    component = distinct(flatten([for k, v in module.cortex.partition_by_labels : v if k == "component"]))
  }
}
resource "kubernetes_namespace" "namespace" {
  metadata {
    name = var.namespace_name
  }
}

module "grafana" {
  source                       = "./module/grafana"
  namespace_name               = kubernetes_namespace.namespace.metadata[0].name
  service_name                 = "grafana"
  service_port                 = var.grafana_port
  container_image              = "grafana/grafana:latest"
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
}

module "shared_etcd" {
  source                       = "./module/etcd"
  namespace_name               = var.namespace_name
  service_name                 = "etcd"
  container_image              = "quay.io/coreos/etcd:v3.5.2"
  cluster_size                 = 1
  storage_volume_size          = 1
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
}

module "kube_state_metrics" {
  source                       = "./module/kube-state-metrics"
  namespace_name               = kubernetes_namespace.namespace.metadata[0].name
  service_name                 = "kube-state-metrics"
  service_port                 = var.kube_state_metrics_port
  container_image              = "k8s.gcr.io/kube-state-metrics/kube-state-metrics:v2.3.0"
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
}

module "grafana_agent" {
  source                       = "./module/grafana-agent"
  namespace_name               = kubernetes_namespace.namespace.metadata[0].name
  resource_name                = "grafana-agent"
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
  agent_container_image        = "grafana/agent:latest"
  agentctl_container_image     = "grafana/agentctl:latest"
  etcd_host                    = module.shared_etcd.client_endpoint_host
  metrics_remote_write_url     = module.cortex.remote_write_url
  logs_remote_write_url        = module.loki.remote_write_url
  partition_by_labels          = local.partition_by_labels
}

module "cortex" {
  source                       = "./module/cortex"
  namespace_name               = kubernetes_namespace.namespace.metadata[0].name
  service_name                 = "cortex"
  service_port                 = var.cortex_port
  container_image              = "quay.io/cortexproject/cortex:v1.11.0"
  storage_volume_size          = 2
  etcd_host                    = module.shared_etcd.client_endpoint_host
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
}

module "loki" {
  source                       = "./module/loki"
  namespace_name               = kubernetes_namespace.namespace.metadata[0].name
  service_name                 = "loki"
  service_port                 = var.loki_port
  container_image              = "grafana/loki:2.4.2"
  storage_volume_size          = 2
  etcd_host                    = module.shared_etcd.client_endpoint_host
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
}