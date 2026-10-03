variable "namespace" {
  type        = string
  description = "Target workload namespace (e.g. clickstream-pipeline)"
  default     = "clickstream-pipeline"
}

variable "keda_namespace" {
  type        = string
  description = "Namespace where KEDA operator is installed"
  default     = "keda"
}

variable "kafka_bootstrap_servers" {
  type        = string
  description = "Kafka broker address"
  default     = "kafka.clickstream-pipeline.svc.cluster.local:9092"
}

variable "kafka_secret_name" {
  type        = string
  description = "Secret containing Kafka SASL credentials"
  default     = "kafka-secrets"
}

variable "kafka_topic" {
  type        = string
  description = "Kafka topic to monitor for consumer lag"
  default     = "clickstream-events"
}

variable "spark_deployment_name" {
  type        = string
  description = "Name of Spark streaming deployment"
  default     = "spark-streaming"
}

variable "spark_consumer_group" {
  type        = string
  description = "Consumer group ID used by Spark"
  default     = "kscep-spark-consumer"
}

variable "spark_lag_threshold" {
  type        = number
  description = "Kafka lag threshold per replica for Spark"
  default     = 50
}

variable "producer_deployment_name" {
  type        = string
  description = "Name of Producer deployment"
  default     = "producer"
}

variable "producer_lag_threshold" {
  type        = number
  description = "Kafka lag threshold per replica for Producer"
  default     = 100
}
