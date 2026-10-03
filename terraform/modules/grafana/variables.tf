variable "namespace" {
  type = string
}

variable "image" {
  type    = string
  default = "grafana/grafana:10.4.2"
}

variable "pg_namespace" {
  type    = string
  default = "clickstream-pipeline"
}

variable "grafana_reader_password" {
  type      = string
  sensitive = true
}
