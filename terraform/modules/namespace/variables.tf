variable "pipeline_namespace" {
  type        = string
  description = "Name of the main pipeline namespace"
  default     = "clickstream-pipeline"
}

variable "monitoring_namespace" {
  type        = string
  description = "Name of the monitoring namespace"
  default     = "monitoring"
}
