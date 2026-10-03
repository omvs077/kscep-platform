locals {
  prometheus_labels = {
    app = "prometheus"
  }
}

resource "kubernetes_config_map_v1" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = var.namespace
  }

  data = {
    "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      rule_files:
        - /etc/prometheus/rules/*.yml

      alerting:
        alertmanagers:
          - static_configs:
              - targets: ['alertmanager:9093']

      scrape_configs:
        - job_name: 'prometheus'
          static_configs:
            - targets: ['localhost:9090']

        - job_name: 'producer-metrics'
          metrics_path: '/metrics'
          static_configs:
            - targets: ['producer.${var.pipeline_namespace}.svc.cluster.local:8080']

        - job_name: 'keda-metrics'
          metrics_path: '/metrics'
          static_configs:
            - targets: ['keda-operator-metrics-apiserver.keda.svc.cluster.local:8080']
          scrape_interval: 30s
    EOT
  }
}

resource "kubernetes_config_map_v1" "prometheus_rules" {
  metadata {
    name      = "prometheus-rules"
    namespace = var.namespace
  }

  data = {
    "alerts.yml" = <<-EOT
      groups:
        - name: pipeline_alerts
          rules:
            - alert: HighDLQRate
              expr: sum(rate(producer_events_rejected_total[2m])) > 1
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "High volume of rejected events in clickstream pipeline"
                description: "Producer is rejecting events at an elevated rate (>1 event/sec)."

            - alert: ProducerPublishRateZero
              expr: sum(rate(producer_events_published_total[5m])) == 0
              for: 2m
              labels:
                severity: warning
              annotations:
                summary: "No clickstream events published"
                description: "Producer has published 0 events in the last 5 minutes."

            - alert: ServicePodCrashLooping
              expr: increase(kube_pod_container_status_restarts_total[5m]) > 2
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "Container crashlooping detected"
                description: "Pod container restarted more than 2 times in 5 minutes."
    EOT
  }
}

resource "kubernetes_service_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
    labels    = local.prometheus_labels
  }

  spec {
    selector = local.prometheus_labels
    port {
      name        = "http"
      port        = 9090
      target_port = 9090
    }
  }
}

resource "kubernetes_deployment_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
    labels    = local.prometheus_labels
  }

  spec {
    replicas = 1
    selector {
      match_labels = local.prometheus_labels
    }

    template {
      metadata {
        labels = local.prometheus_labels
      }

      spec {
        service_account_name = var.prometheus_sa_name

        security_context {
          run_as_user     = 65534
          run_as_group    = 65534
          fs_group        = 65534
          run_as_non_root = true
        }

        container {
          name  = "prometheus"
          image = var.prometheus_image
          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--web.enable-lifecycle"
          ]

          port {
            name           = "http"
            container_port = 9090
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
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
            mount_path = "/etc/prometheus"
          }

          volume_mount {
            name       = "rules"
            mount_path = "/etc/prometheus/rules"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.prometheus_config.metadata[0].name
          }
        }

        volume {
          name = "rules"
          config_map {
            name = kubernetes_config_map_v1.prometheus_rules.metadata[0].name
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
