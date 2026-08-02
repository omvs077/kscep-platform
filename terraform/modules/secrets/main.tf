resource "random_password" "postgres_admin" {
  length  = 16
  special = false
}

resource "random_password" "spark_writer" {
  length  = 16
  special = false
}

resource "random_password" "grafana_reader" {
  length  = 16
  special = false
}

resource "random_password" "kafka_admin" {
  length  = 16
  special = false
}

resource "random_password" "kafka_producer" {
  length  = 16
  special = false
}

resource "random_password" "kafka_spark" {
  length  = 16
  special = false
}

resource "random_password" "kafka_keda" {
  length  = 16
  special = false
}

resource "random_password" "producer_api_key" {
  length  = 24
  special = false
}

# Postgres credentials secret
resource "kubernetes_secret" "postgres_credentials" {
  metadata {
    name      = "postgres-secrets"
    namespace = var.namespace
  }

  data = {
    postgres-password       = random_password.postgres_admin.result
    spark-writer-password   = random_password.spark_writer.result
    grafana-reader-password = random_password.grafana_reader.result
  }

  type = "Opaque"
}

# Kafka SASL credentials secret
resource "kubernetes_secret" "kafka_credentials" {
  metadata {
    name      = "kafka-secrets"
    namespace = var.namespace
  }

  data = {
    admin-password    = random_password.kafka_admin.result
    producer-password = random_password.kafka_producer.result
    spark-password    = random_password.kafka_spark.result
    keda-password     = random_password.kafka_keda.result
  }

  type = "Opaque"
}

# Producer secrets
resource "kubernetes_secret" "producer_secrets" {
  metadata {
    name      = "producer-secrets"
    namespace = var.namespace
  }

  data = {
    admin-api-key = random_password.producer_api_key.result
  }

  type = "Opaque"
}
