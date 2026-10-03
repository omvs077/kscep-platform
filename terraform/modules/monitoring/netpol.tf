resource "kubernetes_network_policy_v1" "monitoring_internal_netpol" {
  metadata {
    name      = "monitoring-internal-netpol"
    namespace = var.namespace
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # Ingress to Prometheus, Alertmanager, Loki
    ingress {
      ports {
        port     = 9090
        protocol = "TCP"
      }
      ports {
        port     = 9093
        protocol = "TCP"
      }
      ports {
        port     = 3100
        protocol = "TCP"
      }
      from {
        pod_selector {}
      }
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.pipeline_namespace }
        }
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

    # Egress to internal monitoring pods
    egress {
      ports {
        port     = 9090
        protocol = "TCP"
      }
      ports {
        port     = 9093
        protocol = "TCP"
      }
      ports {
        port     = 3100
        protocol = "TCP"
      }
      to {
        pod_selector {}
      }
    }

    # Egress from Prometheus to scrape Producer in pipeline namespace
    egress {
      ports {
        port     = 8080
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.pipeline_namespace }
        }
        pod_selector {
          match_labels = { app = "producer" }
        }
      }
    }

    # Egress from Prometheus to scrape KEDA in keda namespace
    egress {
      ports {
        port     = 8080
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "keda" }
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
