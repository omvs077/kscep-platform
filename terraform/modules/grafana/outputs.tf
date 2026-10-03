output "service_name" {
  value = kubernetes_service_v1.grafana.metadata[0].name
}

output "admin_secret_name" {
  value = kubernetes_secret_v1.grafana.metadata[0].name
}
