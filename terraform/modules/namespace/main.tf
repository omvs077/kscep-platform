resource "kubernetes_namespace" "clickstream_pipeline" {
  metadata {
    name = var.pipeline_namespace
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

resource "kubernetes_network_policy" "pipeline_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "monitoring_default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# --- Service Accounts ---

resource "kubernetes_service_account" "producer_sa" {
  metadata {
    name      = "producer-sa"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_service_account" "spark_sa" {
  metadata {
    name      = "spark-sa"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }
  automount_service_account_token = true
}

resource "kubernetes_service_account" "grafana_sa" {
  metadata {
    name      = "grafana-sa"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_service_account" "prometheus_sa" {
  metadata {
    name      = "prometheus-sa"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  automount_service_account_token = true
}

# --- RBAC Rules ---

# Spark-sa: get/list on own ConfigMaps/Secrets
resource "kubernetes_role" "spark_role" {
  metadata {
    name      = "spark-role"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "spark_role_binding" {
  metadata {
    name      = "spark-role-binding"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.spark_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.spark_sa.metadata[0].name
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }
}

# Prometheus-sa: get/list/watch on Pods/Services/Endpoints cluster-wide (read-only)
resource "kubernetes_cluster_role" "prometheus_cluster_role" {
  metadata {
    name = "prometheus-read-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "endpoints", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "prometheus_cluster_role_binding" {
  metadata {
    name = "prometheus-read-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.prometheus_cluster_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus_sa.metadata[0].name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

# KEDA operator RBAC in clickstream-pipeline namespace to scale spark Deployment
resource "kubernetes_role" "keda_scale_role" {
  metadata {
    name      = "keda-scale-role"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments/scale", "deployments"]
    verbs      = ["get", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "keda_scale_role_binding" {
  metadata {
    name      = "keda-scale-role-binding"
    namespace = kubernetes_namespace.clickstream_pipeline.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.keda_scale_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "keda-operator" # Default KEDA Helm chart service account name
    namespace = "kube-system"   # KEDA typically runs in kube-system or its own namespace
  }
}

