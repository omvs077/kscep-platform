variable "namespace" {
  type        = string
  description = "Namespace where monitoring stack is deployed"
  default     = "monitoring"
}

variable "pipeline_namespace" {
  type        = string
  description = "Target workload namespace to scrape"
  default     = "clickstream-pipeline"
}

variable "prometheus_sa_name" {
  type        = string
  description = "Name of existing ServiceAccount for Prometheus"
  default     = "prometheus-sa"
}

variable "prometheus_image" {
  type        = string
  description = "Container image for Prometheus"
  default     = "prom/prometheus:v2.51.0"
}

variable "alertmanager_image" {
  type        = string
  description = "Container image for Alertmanager"
  default     = "prom/alertmanager:v0.27.0"
}

variable "loki_image" {
  type        = string
  description = "Container image for Loki log aggregator"
  default     = "grafana/loki:3.0.0"
}
