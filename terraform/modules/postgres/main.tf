locals {
  labels = { app = "postgres" }
  secret_env = {
    POSTGRES_PASSWORD       = "postgres-password"
    SPARK_WRITER_PASSWORD   = "spark-writer-password"
    GRAFANA_READER_PASSWORD = "grafana-reader-password"
  }
}

resource "kubernetes_config_map_v1" "sql" {
  metadata {
    name      = "postgres-init"
    namespace = var.namespace
  }
  data = {
    "init.sh"    = file("${path.module}/sql/init.sh")
    "schema.sql" = file("${path.module}/sql/schema.sql")
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
  }
  spec {
    selector   = local.labels
    cluster_ip = "None"
    port {
      port = 5432
    }
  }
}

resource "kubernetes_stateful_set_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = var.namespace
  }
  spec {
    service_name = "postgres"
    replicas     = 1
    selector {
      match_labels = local.labels
    }
    template {
      metadata {
        labels = local.labels
      }
      spec {
        security_context {
          run_as_user     = 70
          run_as_non_root = true
          fs_group        = 70
        }
        container {
          name  = "postgres"
          image = var.image
          args  = ["-c", "shared_buffers=64MB", "-c", "max_connections=50"]
          port {
            container_port = 5432
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          dynamic "env" {
            for_each = local.secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = var.secret_name
                  key  = env.value
                }
              }
            }
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
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            period_seconds = 10
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
          volume_mount {
            name       = "sql"
            mount_path = "/docker-entrypoint-initdb.d/init.sh"
            sub_path   = "init.sh"
          }
          volume_mount {
            name       = "sql"
            mount_path = "/sql/schema.sql"
            sub_path   = "schema.sql"
          }
        }
        volume {
          name = "sql"
          config_map {
            name         = kubernetes_config_map_v1.sql.metadata[0].name
            default_mode = "0555"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name      = "data"
        namespace = var.namespace
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = { storage = var.storage }
        }
      }
    }
  }
}