resource "kubernetes_network_policy" "producer_netpol" {
  metadata {
    name      = "producer-netpol"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "producer"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    egress {
      ports {
        port     = "9092"
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
