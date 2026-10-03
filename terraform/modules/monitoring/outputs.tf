output "prometheus_endpoint" {
  value       = "http://${kubernetes_service_v1.prometheus.metadata[0].name}.${var.namespace}.svc.cluster.local:9090"
  description = "Prometheus cluster-internal HTTP endpoint"
}

output "alertmanager_endpoint" {
  value       = "http://${kubernetes_service_v1.alertmanager.metadata[0].name}.${var.namespace}.svc.cluster.local:9093"
  description = "Alertmanager cluster-internal HTTP endpoint"
}

output "loki_endpoint" {
  value       = "http://${kubernetes_service_v1.loki.metadata[0].name}.${var.namespace}.svc.cluster.local:3100"
  description = "Loki cluster-internal HTTP endpoint"
}
