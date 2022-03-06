locals {
  rendered = yamlencode({
    server = {
      http_listen_port = var.agent_container_port
      log_level        = "debug"
    }
    metrics = var.metrics_config == null ? null : module.metrics[0].agent_metrics_config
    logs    = var.logs_config == null ? null : module.logs[0].agent_logs_config
    traces  = var.traces_config == null ? null : module.traces[0].agent_traces_config
    integrations = {
      metrics = var.metrics_config == null ? null : module.metrics[0].agent_integrations_metrics_config
      node_exporter = var.node_exporter_config == null ? null : {
        rootfs_path = var.node_exporter_config.host_root_volume_mount_path
        sysfs_path  = var.node_exporter_config.host_sys_volume_mount_path
        procfs_path = var.node_exporter_config.host_proc_volume_mount_path
      }
    }
  })
}

resource "kubernetes_config_map" "config_map" {
  metadata {
    namespace = var.namespace_name
    name      = var.service_name
  }
  data = {
    (var.config_filename) = local.rendered
  }
}

module "metrics" {
  count                    = var.metrics_config == null ? 0 : 1
  source                   = "./module/metrics"
  namespace_name           = var.namespace_name
  app_name                 = var.service_name
  component_name           = "metrics"
  stateless_node_labels    = var.stateless_node_labels
  agentctl_container_image = var.metrics_config.agentctl_container_image
  agent_host               = var.metrics_config.agent_host
  remote_write_url         = var.metrics_config.remote_write_url
  etcd_host                = var.metrics_config.etcd_host
  refresh_rate             = 5
  partition_by_labels      = var.metrics_config.partition_by_labels
}
locals {
  logs_instance_name = "default"
}
module "logs" {
  count                       = var.logs_config == null ? 0 : 1
  source                      = "./module/logs"
  instance_name               = local.logs_instance_name
  positions_volume_mount_path = var.logs_config.positions_volume_mount_path
  remote_write_url            = var.logs_config.remote_write_url
}

module "traces" {
  count                 = var.traces_config == null ? 0 : 1
  source                = "./module/traces"
  jaeger_receiver_port  = var.traces_config.jaeger_receiver_port
  zipkin_receiver_port  = var.traces_config.zipkin_receiver_port
  remote_write_endpoint = var.traces_config.remote_write_endpoint
  logs_instance_name    = local.logs_instance_name
}