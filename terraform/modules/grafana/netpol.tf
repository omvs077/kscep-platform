resource "kubernetes_network_policy_v1" "grafana_egress" {
  metadata {
    name      = "grafana-egress"
    namespace = var.namespace
  }
  spec {
    pod_selector {
      match_labels = local.labels
    }
    policy_types = ["Egress"]
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
    egress {
      ports {
        port     = 5432
        protocol = "TCP"
      }
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.pg_namespace }
        }
        pod_selector {
          match_labels = { app = "postgres" }
        }
      }
    }
  }
}
