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

resource "kubernetes_manifest" "trigger_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "keda-kafka-auth"
      namespace = var.namespace
    }
    spec = {
      secretTargetRef = [
        {
          parameter = "username"
          name      = var.kafka_secret_name
          key       = "keda-username"
        },
        {
          parameter = "password"
          name      = var.kafka_secret_name
          key       = "keda-password"
        },
        {
          parameter = "sasl"
          name      = var.kafka_secret_name
          key       = "keda-sasl"
        }
      ]
    }
  }

  depends_on = [helm_release.keda]
}

resource "kubernetes_manifest" "spark_scaled_object" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "spark-kafka-scaler"
      namespace = var.namespace
      labels = {
        app = "spark"
      }
    }
    spec = {
      scaleTargetRef = {
        name = var.spark_deployment_name
      }
      minReplicaCount = 1
      maxReplicaCount = 3
      pollingInterval = 15
      cooldownPeriod  = 60
      triggers = [
        {
          type = "kafka"
          metadata = {
            bootstrapServers  = var.kafka_bootstrap_servers
            consumerGroup     = var.spark_consumer_group
            topic             = var.kafka_topic
            lagThreshold      = tostring(var.spark_lag_threshold)
            offsetResetPolicy = "latest"
          }
          authenticationRef = {
            name = "keda-kafka-auth"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.trigger_auth]
}

resource "kubernetes_manifest" "producer_scaled_object" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "producer-kafka-scaler"
      namespace = var.namespace
      labels = {
        app = "producer"
      }
    }
    spec = {
      scaleTargetRef = {
        name = var.producer_deployment_name
      }
      minReplicaCount = 1
      maxReplicaCount = 5
      pollingInterval = 15
      cooldownPeriod  = 60
      triggers = [
        {
          type = "kafka"
          metadata = {
            bootstrapServers  = var.kafka_bootstrap_servers
            consumerGroup     = var.spark_consumer_group
            topic             = var.kafka_topic
            lagThreshold      = tostring(var.producer_lag_threshold)
            offsetResetPolicy = "latest"
          }
          authenticationRef = {
            name = "keda-kafka-auth"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.trigger_auth]
}
