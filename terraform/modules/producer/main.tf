resource "kubernetes_deployment" "producer" {
  metadata {
    name      = "producer"
    namespace = var.namespace
    labels = {
      app = "producer"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "producer"
      }
    }

    template {
      metadata {
        labels = {
          app = "producer"
        }
      }

      spec {
        service_account_name            = "producer-sa"
        automount_service_account_token = false

        security_context {
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          run_as_non_root = true
        }

        container {
          name              = "producer"
          image             = var.image
          image_pull_policy = "Never" # Use local image from minikube cache

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 8080
          }

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = var.bootstrap_servers
          }

          env {
            name  = "KAFKA_TOPIC"
            value = "clickstream-events"
          }

          env {
            name  = "KAFKA_SECURITY_PROTOCOL"
            value = "SASL_PLAINTEXT"
          }

          env {
            name  = "KAFKA_SASL_MECHANISM"
            value = "SCRAM-SHA-512"
          }

          env {
            name  = "KAFKA_SASL_USERNAME"
            value = "producer"
          }

          env {
            name = "KAFKA_SASL_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.kafka_secret_name
                key  = "producer-password"
              }
            }
          }

          env {
            name = "ADMIN_API_KEY"
            value_from {
              secret_key_ref {
                name = var.producer_secret_name
                key  = "admin-api-key"
              }
            }
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "0.25"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/admin/status" # Simple check
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "producer" {
  metadata {
    name      = "producer"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "producer"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}
