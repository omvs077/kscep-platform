locals {
  loki_labels = {
    app = "loki"
  }
}

resource "kubernetes_config_map_v1" "loki_config" {
  metadata {
    name      = "loki-config"
    namespace = var.namespace
  }

  data = {
    "loki.yaml" = <<-EOT
      auth_enabled: false
      server:
        http_listen_port: 3100
        grpc_listen_port: 9096

      common:
        path_prefix: /loki
        storage:
          filesystem:
            chunks_directory: /loki/chunks
            rules_directory: /loki/rules
        replication_factor: 1
        ring:
          kvstore:
            store: inmemory

      schema_config:
        configs:
          - from: 2024-01-01
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h

      limits_config:
        reject_old_samples: true
        reject_old_samples_max_age: 168h
    EOT
  }
}

resource "kubernetes_service_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = var.namespace
    labels    = local.loki_labels
  }

  spec {
    selector = local.loki_labels
    port {
      name        = "http"
      port        = 3100
      target_port = 3100
    }
  }
}

resource "kubernetes_deployment_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = var.namespace
    labels    = local.loki_labels
  }

  spec {
    replicas = 1
    selector {
      match_labels = local.loki_labels
    }

    template {
      metadata {
        labels = local.loki_labels
      }

      spec {
        security_context {
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
          run_as_non_root = true
        }

        container {
          name  = "loki"
          image = var.loki_image
          args  = ["-config.file=/etc/loki/loki.yaml"]

          port {
            name           = "http"
            container_port = 3100
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/loki"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/loki"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.loki_config.metadata[0].name
          }
        }

        volume {
          name = "storage"
          empty_dir {}
        }
      }
    }
  }
}
