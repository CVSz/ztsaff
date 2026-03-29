output "vpc_id" {
  value = module.network.vpc_id
}

output "artifact_bucket" {
  value = module.storage.bucket_name
}
