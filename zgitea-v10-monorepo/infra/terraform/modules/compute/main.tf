variable "name_prefix" { type = string }
variable "subnet_ids" { type = list(string) }

output "worker_group" {
  value = "${var.name_prefix}-workers"
}
