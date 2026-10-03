resource "kubernetes_persistent_volume_claim_v1" "backups" {
  metadata {
    name      = "postgres-backups-pvc"
    namespace = var.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = { storage = "1Gi" }
    }
  }
  wait_until_bound = false
}

locals {
  jobs = {
    partitions = {
      schedule = "5 0 * * *"
      cmd      = "psql -v ON_ERROR_STOP=1 -c 'SELECT ensure_partitions(3)'"
      backup   = false
    }
    backup = {
      schedule = "30 1 * * *"
      cmd      = "pg_dump -Fc -f /backups/clickstream-$(date +%F).dump && find /backups -name '*.dump' -mtime +7 -delete"
      backup   = true
    }
  }
}

resource "kubernetes_cron_job_v1" "maint" {
  for_each = local.jobs
  metadata {
    name      = "postgres-${each.key}"
    namespace = var.namespace
  }
  spec {
    schedule                      = each.value.schedule
    starting_deadline_seconds     = 600
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3
    job_template {
      metadata {}
      spec {
        backoff_limit = 2
        template {
          metadata {
            labels = { app = "postgres-maintenance" }
          }
          spec {
            restart_policy = "OnFailure"
            security_context {
              run_as_user     = 70
              run_as_non_root = true
              fs_group        = 70
            }
            container {
              name    = each.key
              image   = var.image
              command = ["sh", "-c", each.value.cmd]
              env {
                name  = "PGHOST"
                value = "postgres"
              }
              env {
                name  = "PGUSER"
                value = "postgres"
              }
              env {
                name  = "PGDATABASE"
                value = "clickstream"
              }
              env {
                name = "PGPASSWORD"
                value_from {
                  secret_key_ref {
                    name = var.secret_name
                    key  = "postgres-password"
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
                requests = { cpu = "50m", memory = "64Mi" }
                limits   = { memory = "128Mi" }
              }
              dynamic "volume_mount" {
                for_each = each.value.backup ? [1] : []
                content {
                  name       = "backups"
                  mount_path = "/backups"
                }
              }
            }
            dynamic "volume" {
              for_each = each.value.backup ? [1] : []
              content {
                name = "backups"
                persistent_volume_claim {
                  claim_name = kubernetes_persistent_volume_claim_v1.backups.metadata[0].name
                }
              }
            }
          }
        }
      }
    }
  }
}