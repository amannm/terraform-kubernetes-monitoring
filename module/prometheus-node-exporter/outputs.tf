output "service_name" {
  value = kubernetes_service.service.metadata[0].name
}
output "service_port" {
  value = kubernetes_service.service.spec[0].port[0].port
}