variable "namespace" {
  type        = string
  description = "Target namespace"
}

variable "bootstrap_servers" {
  type        = string
  description = "Kafka bootstrap servers"
}

variable "kafka_secret_name" {
  type        = string
  description = "Name of the secret containing Kafka passwords"
}

variable "producer_secret_name" {
  type        = string
  description = "Name of the secret containing producer API key"
}

variable "image" {
  type        = string
  description = "Producer container image"
  default     = "producer:latest"
}

variable "replicas" {
  type        = number
  description = "Number of producer replicas"
  default     = 2
}
