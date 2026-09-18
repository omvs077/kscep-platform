variable "namespace" {
  type        = string
  description = "Target namespace for Kafka"
}

variable "kafka_producer_password" {
  type        = string
  description = "SASL password for producer"
}

variable "kafka_spark_password" {
  type        = string
  description = "SASL password for spark"
}

variable "kafka_keda_password" {
  type        = string
  description = "SASL password for keda"
}

variable "kafka_admin_password" {
  type        = string
  description = "SASL password for admin"
}

variable "replica_count" {
  type        = number
  description = "Number of Kafka brokers"
  default     = 1
}
