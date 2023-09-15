# Custom stuff
# 

variable "cluster_id" {
  type = string
}

variable "thanos_s3_host" {
  type = string
}

variable "thanos_bucket" {
 type = string
}

locals {
}

resource "kubernetes_namespace_v1" "cattle-monitoring-system" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "cattle-monitoring-system"
  }
}
resource "kubernetes_secret_v1" "thanos-container-config" {
  depends_on = [kubernetes_namespace_v1.cattle-monitoring-system]
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
  endpoint: "${var.minio_api_host}"
  bucket: thanos
EOF
  }
}


resource "rancher2_app_v2" "rancher-monitoring" {
  depends_on = [kubernetes_secret_v1.thanos-container-config]
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  cluster_id = var.cluster_id
  values = <<EOT
prometheus:
  prometheusSpec:
    thanos:
      enabled: true
      objectStorageConfig:
        key: "thanos-config.yaml"
        name: "thanos-container-config"
kube-state-metrics:
  metricLabelsAllowlist:
  - pods=[projectid]
EOT
  #chart_version = "9.4.200"
}

resource "rancher2_app_v2" "prometheus-federation" {
  depends_on = [rancher2_app_v2.rancher-monitoring]
  name       = "prometheus-federator"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "prometheus-federator"
  cluster_id = var.cluster_id
}
