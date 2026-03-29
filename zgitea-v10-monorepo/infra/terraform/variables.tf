variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Resource prefix"
  default     = "zgitea-v10"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.42.0.0/16"
}
