output "postgres_secret_name" {
  value = kubernetes_secret.postgres_credentials.metadata[0].name
}

output "kafka_secret_name" {
  value = kubernetes_secret.kafka_credentials.metadata[0].name
}

output "producer_secret_name" {
  value = kubernetes_secret.producer_secrets.metadata[0].name
}

output "postgres_admin_password" {
  value     = random_password.postgres_admin.result
  sensitive = true
}

output "spark_writer_password" {
  value     = random_password.spark_writer.result
  sensitive = true
}

output "grafana_reader_password" {
  value     = random_password.grafana_reader.result
  sensitive = true
}

output "kafka_admin_password" {
  value     = random_password.kafka_admin.result
  sensitive = true
}

output "kafka_producer_password" {
  value     = random_password.kafka_producer.result
  sensitive = true
}

output "kafka_spark_password" {
  value     = random_password.kafka_spark.result
  sensitive = true
}

output "kafka_keda_password" {
  value     = random_password.kafka_keda.result
  sensitive = true
}

output "producer_api_key" {
  value     = random_password.producer_api_key.result
  sensitive = true
}
