variable "cluster_id" {
  type = string
}
variable "minio_api_host" {
  type = string
  default = "minio-service.minio.svc.cluster.local:9000"
}
variable "domain" {
  type = string
}

locals {
  domain = var.domain
  receiver_hostname="thanos-rec${local.domain}"
  querier_hostname="thanos-query${local.domain}"
  bucketweb_hostname="thanos-bucket${local.domain}"
  grafana_hostname="grafana${local.domain}"
}
resource "rancher2_project" "thanos-project" {
  name                      = "thanos"
  cluster_id                = var.cluster_id
  enable_project_monitoring = false
}

resource "rancher2_catalog_v2" "bitnami-thanos" {
  name = "bitnami-thanos"
  cluster_id = var.cluster_id
  url = "https://charts.bitnami.com/bitnami"
}

resource "rancher2_catalog_v2" "grafana" {
  name = "grafana"
  cluster_id = var.cluster_id
  url = "https://grafana.github.io/helm-charts"
}

resource "rancher2_namespace" "namespace" {
  project_id = rancher2_project.thanos-project.id
  name = "thanos"
}

resource "rancher2_app_v2" "thanos-chart" {
  depends_on = [ rancher2_catalog_v2.bitnami-thanos ]
  cluster_id    = var.cluster_id
  name          = "thanos"
  namespace     = "thanos"
  project_id    = rancher2_project.thanos-project.id
  repo_name     = "bitnami-thanos"
  chart_name    = "thanos"
  # chart_version = "0.2.0"
  wait          = true
  # endpoint: "${var.minio_api_host}"
  values        = <<EOT
objstoreConfig: |
  type: S3
  config:
    access_key: minioadmin
    secret_key: minioadmin
    endpoint: "minio-service.minio.svc.cluster.local:9000"
    bucket: thanos
    insecure: true
bucketweb:
  enabled: true
  ingress:
    enabled: true
    hostname: ${local.bucketweb_hostname}
compactor:
  enabled: true
storegateway:
  enabled: true
  retentionResolutionRaw: 2d
  retentionResolution5m: 7d
  retentionResolution1h: 31d
receive:
  enabled: true
  tsdbRetention: 3h
  ingress:
    enabled: true
    hostname: ${local.receiver_hostname}
query:
  ingress:
    enabled: true
    hostname: ${local.querier_hostname}
    stores:
    - receive:10901
    - storeGateway:10901
EOT
}

resource "rancher2_app_v2" "grafana-chart" {
  depends_on = [ rancher2_catalog_v2.grafana ]
  cluster_id    = var.cluster_id
  name          = "grafana"
  namespace     = "thanos"
  project_id    = rancher2_project.thanos-project.id
  repo_name     = "grafana"
  chart_name    = "grafana"
  # chart_version = "0.2.0"
  wait          = true
  # endpoint: "${var.minio_api_host}"
  values        = <<EOT
grafana.ini:
  server:
    domain: ${local.grafana_hostname}
ingress:
  enabled: true
  hosts:
    - "${local.grafana_hostname}"
persistence:
  enabled: true
plugins:
  - volkovlabs-variable-panel
  - grafana-polystat-panel
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Thanos-main
      type: prometheus
      url: http://thanos-query:9090
      isDefault: true
EOT
}

output "querier" {
  value = local.querier_hostname
}
