output "jaeger_endpoint" {
  value = module.grafana_agent.jaeger_endpoint
}
output "zipkin_endpoint" {
  value = module.grafana_agent.zipkin_endpoint
}