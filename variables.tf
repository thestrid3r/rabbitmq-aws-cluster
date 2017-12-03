variable "vpc_id" {}
variable "region" {}
variable "ssh_key_name" {}
variable "rabbitmq_node_count" {
  description = "Number of RabbitMQ nodes"
}
variable "subnet_ids" {
  description = "Subnets for RabbitMQ nodes"
  type = "list"
}
variable "admin_password" {
  description = "Password for 'admin' user"
}
variable "rabbit_password" {
  description = "Password for 'rabbit' user"
}
variable "rabbitmq_secret_cookie" {}

variable "instance_type" {
  default = "t2.small"
}