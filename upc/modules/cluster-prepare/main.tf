# Custom stuff
# 

variable "cluster_id" {
  type = String
}

variable "thanos_s3_host" {
  type = String
}

variable "thanos_bucket" {
 type = String
}

#provider "rancher2" {
  #api_url   = local.labdata.rancher_url
  #token_key = local.labdata.rancher_token
  #insecure  = true
#}
#
#provider "kubernetes" {
  #host                   = local.labdata.rancher_cluster.endpoint
  #client_certificate     = local.labdata.rancher_cluster.client_certificate
  #client_key             = local.labdata.rancher_cluster.client_key
  #cluster_ca_certificate = local.labdata.rancher_cluster.cluster_ca_certificate
#}

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
}

#provider "helm" {
  #kubernetes  {
  #host                   = local.labdata.sample_cluster_ids[0].cluster_data.endpoint
  #client_certificate     = local.labdata.sample_cluster_ids[0].cluster_data.client_certificate
  #client_key             = local.labdata.sample_cluster_ids[0].cluster_data.client_key
  #cluster_ca_certificate = local.labdata.sample_cluster_ids[0].cluster_data.cluster_ca_certificate
  #}
#}

resource "helm_release" "kyverno0" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  wait             = true
}

resource "kubernetes_manifest" "kyverno_policy" {
  depends_on = [ helm_release.kyverno0 ]
  manifest = {
    "apiVersion" = "kyverno.io/v1"
    "kind"       = "ClusterPolicy"
    "metadata"   = {
      "name" = "add-namespace-label-to-pods"
    }
    "spec"       = {
      "background" = true
      "rules"      = [
        {
          "name"     = "copy-namespace-label-to-pods"
          "context"  = [
            {
              "name"    = "namespaceLabels"
              "apiCall" = {
                "urlPath"  = "/api/v1/namespaces/{{request.namespace}}"
                "jmesPath" = "metadata.labels"
              }
            }
          ]
          "match"    = {
            "resources" = {
              "kinds" = ["Pod"]
            }
          }
          "exclude"  = {
            "resources" = {
              "namespaces" = [
                "kube-system",
                "ingress-nginx",
                "kube-node-lease",
                "kube-public",
                "kube-system",
                "kyverno",
                "local",
                "local-path-storage"
              ]
            }
          }
          "mutate"   = {
            "patchStrategicMerge" = {
              "metadata" = {
                "labels" = {
                  "projectid" = "{{ namespaceLabels.\"field.cattle.io/projectId\" || 'unknown' }}"
                }
              }
            }
          }
        }
      ]
    }
  }
}
