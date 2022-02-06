output "api_host" {
  value = "${kubernetes_service.service.metadata[0].name}.${var.namespace_name}.svc.cluster.local:${kubernetes_service.service.spec[0].port[0].port}"
}