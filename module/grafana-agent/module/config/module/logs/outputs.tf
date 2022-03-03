output "agent_logs_config" {
  value = local.logs_config
}
output "logs_instance_name" {
  value = local.logs_config.configs[0].name
}