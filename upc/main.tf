# Custom stuff
# 

data "terraform_remote_state" "sample-lab" {
  backend = "local"
  config = {
    path = "../sample-lab/terraform.tfstate"
  }
}

locals {
  labdata        = data.terraform_remote_state.sample-lab.outputs
  minio_host     = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio"), "https://", ""), "/", "")
  minio_api_host = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio-api"), "https://", ""), "/", "")
}

provider "rancher2" {
  api_url   = local.labdata.rancher_url
  token_key = local.labdata.rancher_token
  insecure  = true
}

provider "kubernetes" {
  alias                  = "rancher"
  host                   = local.labdata.rancher_cluster.endpoint
  client_certificate     = local.labdata.rancher_cluster.client_certificate
  client_key             = local.labdata.rancher_cluster.client_key
  cluster_ca_certificate = local.labdata.rancher_cluster.cluster_ca_certificate
}

resource "kubernetes_namespace_v1" "cattle-monitoring-system" {
  provider = kubernetes.rancher
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "cattle-monitoring-system"
  }
}

resource "kubernetes_secret_v1" "thanos-container-config" {
  depends_on = [kubernetes_namespace_v1.cattle-monitoring-system]
  provider   = kubernetes.rancher
  metadata {
    name      = "thanos-container-config"
    namespace = "cattle-monitoring-system"
  }
  data = {
    "thanos-config.yaml" = <<EOF
type: S3
config:
  access_key: minioadmin
  secret_key: minioadmin
  endpoint: "${local.minio_api_host}"
  bucket: thanos

EOF
  }
}

resource "rancher2_app_v2" "rancher-monitoring-local" {
  depends_on = [kubernetes_secret_v1.thanos-container-config]
  cluster_id = local.labdata.rancher_cluster_cluster_id
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  #chart_version = "9.4.200"
  values = <<EOT
prometheus:
  prometheusSpec:
    thanos:
      enabled: true
      objectStorageConfig: 
        key: "thanos-config.yaml"
        name: "thanos-container-config"
EOT
}

provider "kubernetes" {
  alias                  = "upc-sample0"
  host                   = local.labdata.sample_cluster_ids[0].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[0].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[0].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[0].cluster_data.cluster_ca_certificate
}

resource "kubernetes_namespace_v1" "cattle-monitoring-system-0" {
  lifecycle {
    ignore_changes = [metadata]
  }
  provider = kubernetes.upc-sample0
  metadata {
    name = "cattle-monitoring-system"
  }
}

resource "kubernetes_secret_v1" "thanos-container-config-0" {
  depends_on = [kubernetes_namespace_v1.cattle-monitoring-system-0]
  provider   = kubernetes.upc-sample0
  metadata {
    name      = "thanos-container-config"
    namespace = "cattle-monitoring-system"
  }
  data = {
    "thanos-config.yaml" = <<EOF
type: S3
config:
  access_key: minioadmin
  secret_key: minioadmin
  endpoint: "${local.minio_api_host}"
  bucket: thanos

EOF
  }
}
resource "rancher2_app_v2" "rancher-monitoring0" {
  depends_on = [kubernetes_secret_v1.thanos-container-config-0]
  cluster_id = local.labdata.sample_cluster_ids[0].id
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  values     = <<EOT
prometheus:
  prometheusSpec:
    thanos:
      enabled: true
      objectStorageConfig: 
        key: "thanos-config.yaml"
        name: "thanos-container-config"
EOT
}
#  #chart_version = "9.4.200"
#values = file("values.yaml")
#
#     - action: keep
#       source_labels: [ __meta_kubernetes_pod_label_projectid ]
#     - source_labels: [ __meta_kubernetes_pod_label_projectid ]
#       target_label: projectid
#       action: replace

resource "rancher2_app_v2" "rancher-monitoring1" {
  cluster_id = local.labdata.sample_cluster_ids[1].id
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  #chart_version = "9.4.200"
  #values = file("values.yaml")
}


# Minio install
resource "kubernetes_namespace" "minio" {
  provider = kubernetes.rancher
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "minio"
  }
}

resource "kubernetes_service" "minio_service" {
  provider = kubernetes.rancher
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
  provider = kubernetes.rancher
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
  provider   = kubernetes.rancher
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
  provider   = kubernetes.rancher
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
            value = "https://${local.minio_host}"
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

module "CSR-api" {
  source   = "../modules/CSR"
  dns-name = local.minio_api_host
  ca_key   = local.labdata.ca_cert-key
  ca_cert  = local.labdata.ca_cert-pem
}

module "CSR" {
  source   = "../modules/CSR"
  dns-name = local.minio_host
  ca_key   = local.labdata.ca_cert-key
  ca_cert  = local.labdata.ca_cert-pem
}

resource "kubernetes_secret" "tls-minio-ingress" {
  provider = kubernetes.rancher
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-minio-ingress"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "tls.crt" = module.CSR.cert_pem
    "tls.key" = module.CSR.cert_key
  }
  type = "kubernetes.io/tls"
}

resource "kubernetes_secret" "tls-minio-api-ingress" {
  provider = kubernetes.rancher
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-minio-api-ingress"
    namespace = kubernetes_namespace.minio.metadata[0].name
  }
  data = {
    "tls.crt" = module.CSR-api.cert_pem
    "tls.key" = module.CSR-api.cert_key
  }
  type = "kubernetes.io/tls"
}

resource "kubernetes_ingress_v1" "minio_ingress" {
  provider = kubernetes.rancher
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
      host = local.minio_host

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
      host = local.minio_api_host

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

    # Uncomment the following lines if you have a TLS secret
    tls {
      hosts       = [local.minio_host]
      secret_name = "tls-minio-ingress"
    }
    tls {
      hosts       = [local.minio_api_host]
      secret_name = "tls-minio-api-ingress"
    }
  }
}

provider "minio" {
  minio_server   = kubernetes_ingress_v1.minio_ingress.spec[0].rule[1].host
  minio_user     = "minioadmin"
  minio_password = "minioadmin"
  minio_ssl      = true
  minio_insecure = true
}

resource "minio_s3_bucket" "thanos" {
  bucket = "thanos"
  acl    = "public"
}

output "rancher_url" {
  value = local.labdata.rancher_url
}
output "minio_url" {
  value = "http://${kubernetes_ingress_v1.minio_ingress.spec[0].rule[0].host}"
}

output "bucket_arn" {
  value = minio_s3_bucket.thanos.arn
}
output "bucket_domain" {
  value = minio_s3_bucket.thanos.bucket_domain_name
}

#output "data" {
#value = data.terraform_remote_state.sample-lab
#}
