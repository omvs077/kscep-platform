variable "namespace" { type = string }
variable "image" { default = "postgres:16-alpine" }
variable "secret_name" { default = "postgres-secrets" }
variable "storage" { default = "2Gi" }
variable "spark_pod_label" { default = "spark" }