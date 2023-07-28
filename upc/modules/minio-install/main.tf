variable "CSR" {
  type = any
}

variable "CSR-api" {
  type = any
}

variable "minio_host" {
  type = string
}

variable "minio_api_host" {
  type = string
}

resource "kubernetes_namespace" "minio" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "minio"
  }
}

resource "kubernetes_service" "minio_service" {
  metadata {
    name      = "minio-service"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  spec {
    selector = {
      app = "minio"
    }

    port {
      name        = "server"
      port        = 9000
      target_port = 9000
    }

    port {
      name        = "console"
      port        = 9001
      target_port = 9001
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_persistent_volume_v1" "volume001_pv" {
  metadata {
    name = "minio-data-pv"
  }

  spec {
    capacity = {
      storage = "100Gi"
    }

    access_modes = ["ReadWriteOnce"]
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = ["upc-rancher-control-plane"]
          }
        }
      }
    }
    persistent_volume_reclaim_policy = "Delete"
    storage_class_name               = "local-storage"
    persistent_volume_source {
      local {
        path = "/host"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "minio_data" {
  depends_on = [kubernetes_persistent_volume_v1.volume001_pv]
  metadata {
    name      = "minio-data-pvc"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-storage"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "minio_deployment" {
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  depends_on = [kubernetes_persistent_volume_claim.minio_data]
  metadata {
    name      = "minio-deployment"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "minio"
      }
    }

    template {
      metadata {
        labels = {
          app = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "quay.io/minio/minio"

          args = [
            "server",
            "/data",
            "--console-address",
            ":9001",
          ]

          env {
            name  = "MINIO_BROWSER_REDIRECT_URL"
            value = "https://${var.minio_host}"
          }
          port {
            container_port = 9000
          }

          port {
            container_port = 9001
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "512Mi"
            }

            requests = {
              cpu    = "50m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minio_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "tls-minio-ingress" {
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  metadata {
    name      = "tls-minio-ingress"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "tls.crt" = var.CSR.cert_pem
    "tls.key" = var.CSR.cert_key
  }
  type = "kubernetes.io/tls"
}

resource "kubernetes_secret" "tls-minio-api-ingress" {
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  metadata {
    name      = "tls-minio-api-ingress"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "tls.crt" = var.CSR-api.cert_pem
    "tls.key" = var.CSR-api.cert_key
  }
  type = "kubernetes.io/tls"
}

resource "kubernetes_ingress_v1" "minio_ingress" {
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  metadata {
    name      = "minio-ingress"
    namespace = kubernetes_namespace.minio.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    rule {
      host = var.minio_host

      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.minio_service.metadata[0].name
              port {
                number = 9001
              }
            }
          }
        }
      }
    }
    rule {
      host = var.minio_api_host

      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.minio_service.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = [var.minio_host]
      secret_name = "tls-minio-ingress"
    }
    tls {
      hosts       = [var.minio_api_host]
      secret_name = "tls-minio-api-ingress"
    }
  }
}

output "minio_url" {
  value = "http://${kubernetes_ingress_v1.minio_ingress.spec[0].rule[0].host}"
}
output "minio_host" {
  value = "${kubernetes_ingress_v1.minio_ingress.spec[0].rule[0].host}"
}
output "minio_api_url" {
  value = "http://${kubernetes_ingress_v1.minio_ingress.spec[0].rule[1].host}"
}
output "minio_api_host" {
  value = "${kubernetes_ingress_v1.minio_ingress.spec[0].rule[1].host}"
}
