output "deployment_name" {
  value       = kubernetes_deployment.spark.metadata[0].name
  description = "Name of the Spark deployment"
}

output "checkpoint_pvc_name" {
  value       = kubernetes_persistent_volume_claim.spark_checkpoints.metadata[0].name
  description = "Name of the Spark checkpoints PVC"
}
