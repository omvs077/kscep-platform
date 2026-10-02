resource "kubernetes_deployment" "spark" {
  metadata {
    name      = "spark-streaming"
    namespace = var.namespace
    labels = {
      app = "spark"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "spark"
      }
    }

    template {
      metadata {
        labels = {
          app = "spark"
        }
      }

      spec {
        service_account_name = "spark-sa"

        security_context {
          run_as_user     = 1000
          run_as_group    = 1000
          fs_group        = 1000
          run_as_non_root = true
        }

        container {
          name              = "spark"
          image             = var.image
          image_pull_policy = var.image_pull_policy

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = var.kafka_bootstrap_servers
          }

          env {
            name  = "KAFKA_INPUT_TOPIC"
            value = var.kafka_input_topic
          }

          env {
            name  = "KAFKA_DLQ_TOPIC"
            value = var.kafka_dlq_topic
          }

          env {
            name  = "KAFKA_SASL_USERNAME"
            value = "spark"
          }

          env {
            name = "KAFKA_SASL_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.kafka_secret_name
                key  = "spark-password"
              }
            }
          }

          env {
            name  = "CHECKPOINT_DIR"
            value = "/opt/spark/checkpoints"
          }

          env {
            name  = "POSTGRES_HOST"
            value = var.postgres_host
          }

          env {
            name  = "POSTGRES_PORT"
            value = var.postgres_port
          }

          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }

          env {
            name  = "POSTGRES_USER"
            value = var.postgres_user
          }

          volume_mount {
            name       = "checkpoints-vol"
            mount_path = "/opt/spark/checkpoints"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1024Mi"
            }
          }
        }

        volume {
          name = "checkpoints-vol"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.spark_checkpoints.metadata[0].name
          }
        }
      }
    }
  }
}
