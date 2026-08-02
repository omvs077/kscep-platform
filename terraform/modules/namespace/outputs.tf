output "pipeline_namespace_name" {
  value = kubernetes_namespace.clickstream_pipeline.metadata[0].name
}

output "monitoring_namespace_name" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}
