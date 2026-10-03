locals {
  labels = { app = "grafana" }
  dashboards = {
    "executive.json"   = file("${path.module}/files/dashboards/executive.json")
    "engineering.json" = file("${path.module}/files/dashboards/engineering.json")
    "infra-ops.json"   = file("${path.module}/files/dashboards/infra-ops.json")
  }
  provisioning = {
    "datasources.yaml" = file("${path.module}/files/datasources.yaml")
    "dashboards.yaml"  = file("${path.module}/files/dashboards.yaml")
  }
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana" {
  metadata {
    name      = "grafana-secrets"
    namespace = var.namespace
  }
  data = {
    admin-password  = random_password.admin.result
    reader-password = var.grafana_reader_password
  }
}

resource "kubernetes_config_map_v1" "provisioning" {
  metadata {
    name      = "grafana-provisioning"
    namespace = var.namespace
  }
  data = local.provisioning
}

resource "kubernetes_config_map_v1" "dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = var.namespace
  }
  data = local.dashboards
}

resource "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
  }
  spec {
    selector = local.labels
    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = local.labels
    }
    template {
      metadata {
        labels = local.labels
        annotations = {
          config-hash = sha1(jsonencode([local.provisioning, local.dashboards]))
        }
      }
      spec {
        automount_service_account_token = false
        security_context {
          run_as_user     = 472
          run_as_group    = 472
          fs_group        = 472
          run_as_non_root = true
        }
        container {
          name  = "grafana"
          image = var.image
          port {
            container_port = 3000
          }
          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }
          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.grafana.metadata[0].name
                key  = "admin-password"
              }
            }
          }
          env {
            name = "PG_READER_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.grafana.metadata[0].name
                key  = "reader-password"
              }
            }
          }
          env {
            name  = "GF_USERS_ALLOW_SIGN_UP"
            value = "false"
          }
          env {
            name  = "GF_ANALYTICS_REPORTING_ENABLED"
            value = "false"
          }
          env {
            name  = "GF_ANALYTICS_CHECK_FOR_UPDATES"
            value = "false"
          }
          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { memory = "256Mi" }
          }
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            period_seconds = 10
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }
          volume_mount {
            name       = "provisioning"
            mount_path = "/etc/grafana/provisioning/datasources/datasources.yaml"
            sub_path   = "datasources.yaml"
          }
          volume_mount {
            name       = "provisioning"
            mount_path = "/etc/grafana/provisioning/dashboards/dashboards.yaml"
            sub_path   = "dashboards.yaml"
          }
          volume_mount {
            name       = "dashboards"
            mount_path = "/etc/grafana/dashboards"
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
        volume {
          name = "provisioning"
          config_map {
            name = kubernetes_config_map_v1.provisioning.metadata[0].name
          }
        }
        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map_v1.dashboards.metadata[0].name
          }
        }
      }
    }
  }
}
