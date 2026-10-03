resource "kubernetes_network_policy_v1" "keda_operator_netpol" {
  metadata {
    name      = "keda-operator-netpol"
    namespace = kubernetes_namespace.keda.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # Ingress from API server and monitoring to KEDA metrics server
    ingress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      ports {
        port     = 8080
        protocol = "TCP"
      }
      ports {
        port     = 6443
        protocol = "TCP"
      }
    }

    # Egress to DNS
    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
      }
    }

    # Egress to Kafka in clickstream-pipeline namespace
    egress {
      ports {
        port     = 9092
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.namespace }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "kafka" }
        }
      }
    }

    # Egress to Kubernetes API Server
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      ports {
        port     = 6443
        protocol = "TCP"
      }
      ports {
        port     = 8443
        protocol = "TCP"
      }
    }
  }
}
