output "keda_namespace_name" {
  value       = kubernetes_namespace.keda.metadata[0].name
  description = "Namespace where KEDA is deployed"
}

output "spark_scaled_object_name" {
  value       = "spark-kafka-scaler"
  description = "Name of the ScaledObject for Spark"
}

output "producer_scaled_object_name" {
  value       = "producer-kafka-scaler"
  description = "Name of the ScaledObject for Producer"
}
