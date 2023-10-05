# Custom stuff
# 

variable "cluster_id" {
  type = string
}

variable "rancher_url" {
  type = string
}
variable "thanos_s3_host" {
  type = string
}

variable "thanos_bucket" {
 type = string
}

variable "minio_api_host" {
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
  #chart_version = "9.4.200"
  wait = true
  cluster_id = var.cluster_id
  values = <<EOT
prometheus:
 prometheusSpec:
   podMonitorSelector:
     matchLabels:
        app.kubernetes.io/instance: rancher-monitoring
   serviceMonitorSelector:
     matchLabels:
        app.kubernetes.io/instance: rancher-monitoring
#   ruleNamespaceSelector:
#     matchNames: 
#     - cattle-system
#     - cattle-monitoring-system
#   serviceMonitorNamespaceSelector:
#     matchNames: 
#     - cattle-system
#     - cattle-monitoring-system
#   podMonitorNamespaceSelector:
#     matchNames: 
#     - cattle-system
#     - cattle-monitoring-system
  remoteWrite:
  - name: thanos
    url: "http://thanos-query-172.18.0.2.sslip.io/api/v1/receive"
  externalLabels:
    tenant: "System"
    tenant_id: "system"
    project:  "System"
    project_id: "p-system"
            
#kube-state-metrics:
  #namespaces: "cattle-system,cattle-monitoring-system,cattle-dashboards,cattle-fleet-system,cattle-impersonation-system,cattle-monitoring-system,kube-node-lease,kube-public,kube-system,kyverno"
EOT
}

data "rancher2_project" "system" {
  cluster_id = var.cluster_id
  name = "System"
}

resource "rancher2_app_v2" "prometheus-federation" {
  depends_on = [rancher2_app_v2.rancher-monitoring]
  name       = "prometheus-federator"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "prometheus-federator"
  wait = true
  cluster_id = var.cluster_id
  values = <<EOT
global:
  cattle:
    systemProjectId: ${split(":",data.rancher2_project.system.id)[1]}
    url: ${trim(var.rancher_url,"/")}
helmProjectOperator:
  global:
    cattle:
      systemProjectId: ${split(":",data.rancher2_project.system.id)[1]}
      url: ${trim(var.rancher_url,"/")}
EOT
}
