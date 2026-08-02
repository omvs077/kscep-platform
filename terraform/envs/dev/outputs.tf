output "pipeline_namespace" {
  value = module.namespace.pipeline_namespace_name
}

output "monitoring_namespace" {
  value = module.namespace.monitoring_namespace_name
}

output "postgres_secret_name" {
  value = module.secrets.postgres_secret_name
}

output "kafka_secret_name" {
  value = module.secrets.kafka_secret_name
}

output "producer_secret_name" {
  value = module.secrets.producer_secret_name
}
