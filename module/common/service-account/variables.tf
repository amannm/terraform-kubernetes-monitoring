variable "namespace_name" {
  type = string
}
variable "service_account_name" {
  type = string
}
variable "role_name" {
  type    = string
  default = null
}
variable "annotations" {
  type    = map(string)
  default = null
}