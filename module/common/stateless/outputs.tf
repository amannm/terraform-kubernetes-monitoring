output "hostname" {
  value = module.service.non_headless_service_hostname
}
output "headless_hostname" {
  value = module.service.headless_service_hostname
}
output "service_name" {
  value = local.service_name
}