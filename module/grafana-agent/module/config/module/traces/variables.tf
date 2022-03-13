variable "jaeger_receiver_port" {
  type = number
}
variable "zipkin_receiver_port" {
  type = number
}
variable "otlp_grpc_receiver_port" {
  type = number
}
variable "remote_write_endpoint" {
  type = string
}
variable "logs_instance_name" {
  type = string
}