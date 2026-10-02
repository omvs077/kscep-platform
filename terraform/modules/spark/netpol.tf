resource "kubernetes_network_policy" "spark_netpol" {
  metadata {
    name      = "spark-netpol"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "spark"
      }
    }

    policy_types = ["Egress"]

    # Allow Egress to DNS in kube-system
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    # Allow Egress to Kafka broker
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kafka"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9092"
      }
    }

    # Allow Egress to PostgreSQL
    egress {
      to {
        pod_selector {
          match_labels = {
            app = "postgres"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
