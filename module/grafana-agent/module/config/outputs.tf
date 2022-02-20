output "config_map_name" {
  value = kubernetes_config_map.config_map.metadata[0].name
}