resource "kubernetes_namespace" "keda" {
  metadata {
    name = var.keda_namespace
    labels = {
      "app.kubernetes.io/part-of" = "kscep-platform"
      "name"                      = var.keda_namespace
    }
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "~> 2.14.0"
  namespace  = kubernetes_namespace.keda.metadata[0].name

  set {
    name  = "crds.install"
    value = "true"
  }

  set {
    name  = "resources.operator.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.operator.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.operator.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.metricServer.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.metricServer.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.metricServer.limits.memory"
    value = "256Mi"
  }
}

resource "helm_release" "keda_resources" {
  name      = "keda-resources"
  chart     = "${path.module}/keda-resources"
  namespace = var.namespace

  set {
    name  = "namespace"
    value = var.namespace
  }

  set {
    name  = "kafkaSecretName"
    value = var.kafka_secret_name
  }

  set {
    name  = "kafkaBootstrapServers"
    value = var.kafka_bootstrap_servers
  }

  set {
    name  = "kafkaTopic"
    value = var.kafka_topic
  }

  set {
    name  = "sparkDeploymentName"
    value = var.spark_deployment_name
  }

  set {
    name  = "sparkConsumerGroup"
    value = var.spark_consumer_group
  }

  set {
    name  = "sparkLagThreshold"
    value = tostring(var.spark_lag_threshold)
  }

  set {
    name  = "producerDeploymentName"
    value = var.producer_deployment_name
  }

  set {
    name  = "producerLagThreshold"
    value = tostring(var.producer_lag_threshold)
  }

  depends_on = [helm_release.keda]
}
