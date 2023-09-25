variable "cluster-name" {
  type = string
}
variable "cluster-description" {
  type = string
}
variable "ca-cert-pem" {
  type = string
}
data "rancher2_setting" "server_version" {
  name = "server-version"
}
data "rancher2_setting" "install_uuid" {
  name = "install-uuid"
}
data "rancher2_setting" "server_url" {
  name = "server-url"
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  wait             = true
}
#
# Namespace
resource "kubernetes_namespace" "cattle_agent_system" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "cattle-system"
  }
}

resource "rancher2_cluster" "rancher-server" {
  name        = var.cluster-name
  description = var.cluster-description
  depends_on = [ kubernetes_namespace.cattle_agent_system ]
}


resource "rancher2_cluster_sync" "wait-sync" {
  depends_on = [ kubernetes_service.cattle_cluster_agent,
  kubernetes_deployment.cattle_cluster_agent ]
  cluster_id =  rancher2_cluster.rancher-server.id
}

resource "rancher2_catalog_v2" "stresser" {
  depends_on = [ rancher2_cluster_sync.wait-sync ]
  name = "stresser"
  cluster_id = rancher2_cluster.rancher-server.id
  url = "https://charts.sudermanjr.com"
  #git_repo = "https://github.com/weinong/stress-helm-chart.git"
  #git_branch = "master"
}
# MANIFEST FOR CLUSTER REGISTRATION

# Cluster role
resource "kubernetes_cluster_role" "proxy_clusterrole_kubeapiserver" {
  #depends_on = [ kubernetes_namespace.cattle_agent_system ]
  lifecycle {
    ignore_changes = all
  }
  metadata {
    name = "proxy-clusterrole-kubeapiserver"
  }
  rule {
    verbs      = ["get", "list", "watch", "create"]
    api_groups = [""]
    resources  = ["nodes/metrics", "nodes/proxy", "nodes/stats", "nodes/log", "nodes/spec"]
  }

}

# Cluster role binding
resource "kubernetes_cluster_role_binding" "proxy_role_binding_kubernetes_master" {
  lifecycle {
    ignore_changes = all
  }
  metadata {
    name = "proxy-role-binding-kubernetes-master"
  }
  subject {
    kind = "User"
    name = "kube-apiserver"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "proxy-clusterrole-kubeapiserver"
  }

}


# Service account
resource "kubernetes_service_account" "cattle" {
  depends_on = [ kubernetes_namespace.cattle_agent_system ]
 lifecycle {
   ignore_changes = all
 }
  metadata {
    name      = "cattle"
    namespace = "cattle-system"
  }

  #depends_on = [kubernetes_namespace.cattle_system]
  
  #depends_on = [ rancher2_cluster_sync.wait-sync ]
  #depends_on = [ rancher2_cluster.rancher-server ]
}

# Cluster role binding
resource "kubernetes_cluster_role_binding" "cattle_admin_binding" {
  lifecycle {
    ignore_changes = all
  }
  metadata {
    name = "cattle-admin-binding"
    labels = {
      "cattle.io/creator" = "norman"
    }
  }
  subject {
    kind      = "ServiceAccount"
    name      = "cattle"
    namespace = "cattle-system"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cattle-admin"
  }

  depends_on = [kubernetes_service_account.cattle, 
    kubernetes_cluster_role.cattle_admin,
    kubernetes_namespace.cattle_agent_system ]
}

resource "kubernetes_secret" "catle_credentials_rancher-server" {
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
  metadata {
    name      = "cattle-credentials-rancher-server"
    namespace = "cattle-system"
  }
  data = {
    token = rancher2_cluster.rancher-server.cluster_registration_token.0.token
    url   = data.rancher2_setting.server_url.value #"https://192.168.1.100.sslip.io"
  }
  type       = "Opaque"
  #depends_on = [kubernetes_namespace.cattle_system]
  #depends_on = [ rancher2_cluster.rancher-server ]
  depends_on = [ kubernetes_namespace.cattle_agent_system ]
}

# Cluster role
resource "kubernetes_cluster_role" "cattle_admin" {
  lifecycle {
    ignore_changes = all
  }
  metadata {
    name = "cattle-admin"
    labels = {
      "cattle.io/creator" = "norman"
    }
  }
  rule {
    verbs      = ["*"]
    api_groups = ["*"]
    resources  = ["*"]
  }
  rule {
    verbs             = ["*"]
    non_resource_urls = ["*"]
  }

}

# Deployment
resource "kubernetes_deployment" "cattle_cluster_agent" {
  lifecycle {
  ignore_changes = all
  }
  metadata {
    name      = "cattle-cluster-agent"
    namespace = "cattle-system"
    annotations = {
      "management.cattle.io/scale-available" = "2"
    }
  }
  spec {
    selector {
      match_labels = {
        app = "cattle-cluster-agent"
      }
    }
    template {
      metadata {
        labels = {
          app = "cattle-cluster-agent"
        }
      }
      spec {
        volume {
          name = "cattle-credentials"
          secret {
            secret_name  = "cattle-credentials-rancher-server"
            default_mode = "0500"
          }
        }
        container {
          name  = "cluster-register"
          image = "rancher/rancher-agent:${data.rancher2_setting.server_version.value}"
          env {
            name  = "CATTLE_IS_RKE"
            value = "false"
          }
          env {
            name  = "CATTLE_SERVER"
            value = data.rancher2_setting.server_url.value
          }
          env {
            name  = "CATTLE_CA_CHECKSUM"
            value = sha256(var.ca-cert-pem) #module.CA.ca-cert-pem
          }
          env {
            name  = "CATTLE_CLUSTER"
            value = "true"
          }
          env {
            name  = "CATTLE_K8S_MANAGED"
            value = "true"
          }
          env {
            name = "CATTLE_CLUSTER_REGISTRY"
          }
          env {
            name  = "CATTLE_SERVER_VERSION"
            value = data.rancher2_setting.server_version.value
          }
          env {
            name  = "CATTLE_INSTALL_UUID"
            value = data.rancher2_setting.install_uuid.value
          }
          env {
            name  = "CATTLE_INGRESS_IP_DOMAIN"
            value = "sslip.io"
          }
          volume_mount {
            name       = "cattle-credentials"
            read_only  = true
            mount_path = "/cattle-credentials"
          }
          image_pull_policy = "IfNotPresent"
        }
        service_account_name = "cattle"
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "beta.kubernetes.io/os"
                  operator = "NotIn"
                  values   = ["windows"]
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              preference {
                match_expressions {
                  key      = "node-role.kubernetes.io/controlplane"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              preference {
                match_expressions {
                  key      = "node-role.kubernetes.io/control-plane"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              preference {
                match_expressions {
                  key      = "node-role.kubernetes.io/master"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              preference {
                match_expressions {
                  key      = "cattle.io/cluster-agent"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
          }
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["cattle-cluster-agent"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        toleration {
          key    = "node-role.kubernetes.io/controlplane"
          value  = "true"
          effect = "NoSchedule"
        }
        toleration {
          key      = "node-role.kubernetes.io/control-plane"
          operator = "Exists"
          effect   = "NoSchedule"
        }
        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge = "1"
      }
    }
  }

  #depends_on = [kubernetes_service_account.cattle, kubernetes_namespace.cattle_system]
  depends_on = [kubernetes_service_account.cattle, 
                kubernetes_namespace.cattle_agent_system ]
}

# Service definition
resource "kubernetes_service" "cattle_cluster_agent" {
  #lifecycle {
  #ignore_changes = all
  #}
  metadata {
    name      = "cattle-cluster-agent"
    namespace = "cattle-system"
  }
  spec {
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = "80"
    }
    port {
      name        = "https-internal"
      protocol    = "TCP"
      port        = 443
      target_port = "444"
    }
    selector = {
      app = "cattle-cluster-agent"
    }
  }

  #depends_on = [kubernetes_namespace.cattle_system]

  #depends_on = [rancher2_cluster.rancher-server]
  depends_on = [ kubernetes_namespace.cattle_agent_system ]
}

#resource "rancher2_cluster_sync" "wait-sync" {
#  cluster_id = rancher2_cluster.rancher-server.id
#}

output "cluster_id" {
  value = rancher2_cluster.rancher-server.id
}
#resource "rancher2_app_v2" "rancher-monitoring" {
#depends_on = [kubernetes_deployment.cattle_cluster_agent]
#cluster_id = rancher2_cluster.rancher-server.id
#name       = "rancher-monitoring"
#namespace  = "cattle-monitoring-system"
#repo_name  = "rancher-charts"
#chart_name = "rancher-monitoring"
##chart_version = "9.4.200"
##values = file("values.yaml")
#}


