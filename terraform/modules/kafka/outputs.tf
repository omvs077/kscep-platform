output "bootstrap_servers" {
  value = "kafka.${var.namespace}.svc.cluster.local:9092"
}
