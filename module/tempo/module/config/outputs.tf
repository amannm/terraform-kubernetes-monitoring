output "config_map_name" {
  value = local.config_map_name
}
output "config_filename" {
  value = local.config_filename
}
output "config_checksum" {
  value = sha256(local.rendered)
}
output "config_mount_path" {
  value = local.config_mount_path
}
output "storage_mount_path" {
  value = local.storage_mount_path
}
output "service_http_port" {
  value = local.http_port
}
output "service_grpc_port" {
  value = local.grpc_port
}
output "etcd_host" {
  value = local.etcd_host
}