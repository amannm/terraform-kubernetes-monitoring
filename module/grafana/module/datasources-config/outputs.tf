output "config_map_name" {
  value = local.config_map_name
}
output "config_filename" {
  value = local.config_filename
}
output "config_checksum" {
  value = sha256(local.rendered)
}