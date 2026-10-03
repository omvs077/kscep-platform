resource "kubernetes_network_policy" "kafka_netpol" {
  metadata {
    name      = "kafka-netpol"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "kafka"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      # Client traffic from producer (and later spark, keda)
      ports {
        port     = "9092"
        protocol = "TCP"
      }
      from {
        pod_selector {
          match_labels = {
            app = "producer"
          }
        }
      }
      from {
        pod_selector {
          match_labels = {
            app = "spark"
          }
        }
      }
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kafka"
          }
        }
      }
    }

    # Inter-broker and controller ingress
    ingress {
      ports {
        port     = "9093"
        protocol = "TCP"
      }
      ports {
        port     = "9094"
        protocol = "TCP"
      }
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kafka"
          }
        }
      }
    }

    # Inter-broker and controller egress
    egress {
      ports {
        port     = "9092"
        protocol = "TCP"
      }
      ports {
        port     = "9093"
        protocol = "TCP"
      }
      ports {
        port     = "9094"
        protocol = "TCP"
      }
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kafka"
          }
        }
      }
    }
  }
}
