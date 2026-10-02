variable "namespace" {
  type        = string
  description = "Target namespace for Spark streaming job"
  default     = "clickstream-pipeline"
}

variable "image" {
  type        = string
  description = "Spark container image"
  default     = "spark:latest"
}

variable "image_pull_policy" {
  type        = string
  description = "Image pull policy"
  default     = "IfNotPresent"
}

variable "replicas" {
  type        = number
  description = "Replica count for Spark deployment"
  default     = 1
}

variable "kafka_bootstrap_servers" {
  type        = string
  description = "Kafka bootstrap broker address"
  default     = "kafka.clickstream-pipeline.svc.cluster.local:9092"
}

variable "kafka_input_topic" {
  type        = string
  description = "Kafka topic to consume clickstream events from"
  default     = "clickstream-events"
}

variable "kafka_dlq_topic" {
  type        = string
  description = "Kafka topic to route poisoned or malformed events to"
  default     = "clickstream-events-dlq"
}

variable "kafka_secret_name" {
  type        = string
  description = "Secret name containing Kafka passwords"
  default     = "kafka-secrets"
}

variable "checkpoint_pvc_size" {
  type        = string
  description = "Size of PVC for Spark streaming checkpoints"
  default     = "1Gi"
}

variable "postgres_host" {
  type        = string
  description = "PostgreSQL host"
  default     = "postgres.clickstream-pipeline.svc.cluster.local"
}

variable "postgres_port" {
  type        = string
  description = "PostgreSQL port"
  default     = "5432"
}

variable "postgres_db" {
  type        = string
  description = "PostgreSQL database name"
  default     = "clickstream"
}

variable "postgres_user" {
  type        = string
  description = "PostgreSQL user for Spark"
  default     = "spark_writer"
}
