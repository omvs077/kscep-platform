output "service_name" {
  value = kubernetes_service.producer.metadata[0].name
}

output "service_port" {
  value = kubernetes_service.producer.spec[0].port[0].port
}
