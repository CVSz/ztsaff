terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source      = "./modules/network"
  name_prefix = var.name_prefix
  cidr_block  = var.vpc_cidr
}

module "storage" {
  source      = "./modules/storage"
  name_prefix = var.name_prefix
}

module "compute" {
  source      = "./modules/compute"
  name_prefix = var.name_prefix
  subnet_ids  = module.network.private_subnet_ids
}
