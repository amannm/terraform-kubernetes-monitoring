locals {
  config_volume_mount_path  = "/etc/grafana"
  storage_volume_mount_path = "/var/lib/grafana"
  rendered                  = <<-EOT
  [paths]
  data = ${local.storage_volume_mount_path}
  temp_data_lifetime = 24h
  logs = ${local.storage_volume_mount_path}/log
  plugins = ${local.storage_volume_mount_path}/plugins
  provisioning = ${var.provisioning_config_directory}

  [server]
  protocol = http
  http_port = ${var.container_port}

  [analytics]
  reporting_enabled = false
  check_for_updates = true

  [snapshots]
  external_enabled = false

  [log]
  mode = console
  level = info

  [metrics]
  enabled = true

  EOT

}


locals {
  config_map_name = kubernetes_config_map.config_map.metadata[0].name
  config_filename = var.config_filename
}
resource "kubernetes_config_map" "config_map" {
  metadata {
    name      = var.config_map_name
    namespace = var.namespace_name
  }
  data = {
    (local.config_filename) = local.rendered
  }
}