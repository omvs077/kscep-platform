resource "kubernetes_network_policy_v1" "postgres_ingress" {
  metadata {
    name      = "postgres-ingress"
    namespace = var.namespace
  }
  spec {
    pod_selector {
      match_labels = local.labels
    }
    policy_types = ["Ingress"]
    ingress {
      ports {
        port     = 5432
        protocol = "TCP"
      }
      from {
        pod_selector {
          match_labels = { app = var.spark_pod_label }
        }
      }
      from {
        pod_selector {
          match_labels = { app = "postgres-maintenance" }
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "maintenance_egress" {
  metadata {
    name      = "postgres-maintenance-egress"
    namespace = var.namespace
  }
  spec {
    pod_selector {
      match_labels = { app = "postgres-maintenance" }
    }
    policy_types = ["Egress"]
    egress {
      ports {
        port     = 5432
        protocol = "TCP"
      }
      to {
        pod_selector {
          match_labels = local.labels
        }
      }
    }
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
  }
}