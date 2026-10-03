locals {
  alertmanager_labels = {
    app = "alertmanager"
  }
}

resource "kubernetes_config_map_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = var.namespace
  }

  data = {
    "alertmanager.yml" = <<-EOT
      global:
        resolve_timeout: 5m

      route:
        group_by: ['alertname', 'severity']
        group_wait: 10s
        group_interval: 30s
        repeat_interval: 1h
        receiver: 'default-receiver'

      receivers:
        - name: 'default-receiver'
    EOT
  }
}

resource "kubernetes_service_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = var.namespace
    labels    = local.alertmanager_labels
  }

  spec {
    selector = local.alertmanager_labels
    port {
      name        = "http"
      port        = 9093
      target_port = 9093
    }
  }
}

resource "kubernetes_deployment_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = var.namespace
    labels    = local.alertmanager_labels
  }

  spec {
    replicas = 1
    selector {
      match_labels = local.alertmanager_labels
    }

    template {
      metadata {
        labels = local.alertmanager_labels
      }

      spec {
        security_context {
          run_as_user     = 65534
          run_as_group    = 65534
          fs_group        = 65534
          run_as_non_root = true
        }

        container {
          name  = "alertmanager"
          image = var.alertmanager_image
          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager"
          ]

          port {
            name           = "http"
            container_port = 9093
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
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
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/alertmanager"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.alertmanager_config.metadata[0].name
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
