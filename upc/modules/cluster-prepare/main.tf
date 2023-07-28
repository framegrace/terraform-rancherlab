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
   # Modifu this to add/remove/change the default recording-rules
   rule_groups = [
    {
      name     = "project_cpu_usage"
      interval = "1m"
      rules    = [
        {
          record = "project:container_cpu_usage_seconds_total:rate1m"
          expr   = <<-EOF
            sum(
              rate(container_cpu_usage_seconds_total[1m]) * on (namespace, pod) group_left(label_projectid, cluster_id)
              kube_pod_labels{label_projectid!=""}
            ) by (pod, namespace, label_projectid, cluster_id)
          EOF
        }
      ]
    },
    {
      name     = "project_pod_resource_requests"
      interval = "1m"
      rules    = [
        {
          record = "project:kube_pod_container_resource_requests"
          expr   = <<-EOF
            sum(
              kube_pod_container_resource_requests * on (namespace, pod) group_left(label_projectid, cluster_id)
              kube_pod_labels{label_projectid!=""}
            ) by (pod, namespace, label_projectid, cluster_id, resource)
          EOF
        }
      ]
    },
    {
      name     = "project_pod_resource_limits"
      interval = "1m"
      rules    = [
        {
          record = "project:kube_pod_container_resource_limits"
          expr   = <<-EOF
            sum(
              kube_pod_container_resource_limits * on (namespace, pod) group_left(label_projectid, cluster_id)
              kube_pod_labels{label_projectid!=""}
            ) by (pod, namespace, label_projectid, cluster_id, resource)
          EOF
        }
      ]
    }
  ]
}

resource "kubernetes_manifest" "kyverno_policy" {
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
  endpoint: "${var.thanos_s3_host}"
  bucket: "${var.thanos_bucket}"
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

resource "kubernetes_manifest" "prometheus_rule" {
  depends_on = [ rancher2_app_v2.rancher-monitoring ]
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      labels = {
        prometheus = "k8s"
        role       = "recording-rules"
      }
      name      = "project-metrics-k8s-rules"
      namespace = "cattle-monitoring-system"
    }
    spec = {
      groups = [for group in local.rule_groups : {
        name     = group.name
        interval = group.interval
        rules    = [for rule in group.rules : {
          record = rule.record
          expr   = rule.expr
        }]
      }]
    }
  }
}

