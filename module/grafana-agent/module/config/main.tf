resource "kubernetes_config_map" "config_map" {
  metadata {
    namespace = var.namespace_name
    name      = var.service_name
  }
  data = {
    (var.config_filename) = yamlencode({
      server = {
        http_listen_port = var.agent_container_port
        log_level        = "info"
      }
      metrics = var.metrics_config == null ? null : module.metrics[0].agent_metrics_config
      logs    = var.logs_config == null ? null : module.logs[0].agent_logs_config
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
}

module "metrics" {
  count                        = var.metrics_config == null ? 0 : 1
  source                       = "./module/metrics"
  namespace_name               = var.namespace_name
  resource_name                = "${var.service_name}-metrics"
  preemptible_node_label_name  = var.preemptible_node_label_name
  preemptible_node_label_value = var.preemptible_node_label_value
  agentctl_container_image     = var.metrics_config.agentctl_container_image
  agent_host                   = var.metrics_config.agent_host
  remote_write_url             = var.metrics_config.remote_write_url
  etcd_host                    = var.metrics_config.etcd_host
  refresh_rate                 = 30
}

module "logs" {
  count                       = var.logs_config == null ? 0 : 1
  source                      = "./module/logs"
  positions_volume_mount_path = var.logs_config.positions_volume_mount_path
  remote_write_url            = var.logs_config.remote_write_url
}