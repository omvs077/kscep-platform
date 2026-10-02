resource "kubernetes_persistent_volume_claim" "spark_checkpoints" {
  metadata {
    name      = "spark-checkpoints-pvc"
    namespace = var.namespace
    labels = {
      app = "spark"
    }
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.checkpoint_pvc_size
      }
    }
  }
}
