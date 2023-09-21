
variable "CA" {
  type = object({
    ca-cert-pem     = string
    ca-priv-key-pem = string
  })
}

variable "hostname" {
  type = string
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  wait             = true
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io/"
  chart            = "cert-manager"
  version          = "v1.11.0"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = false
  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_namespace" "rancher_cattle_system" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name = "cattle-system"
  }
}

resource "kubernetes_secret" "tls-ca" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-ca"
    namespace = "cattle-system"
  }
  data = {
    "cacerts.pem" = var.CA.ca-cert-pem
  }
  type       = "generic"
  depends_on = [kubernetes_namespace.rancher_cattle_system]
}

module "CSR" {
  source   = "../CSR"
  dns-name = var.hostname
  ca_key   = var.CA.ca-priv-key-pem
  ca_cert  = var.CA.ca-cert-pem
}

resource "kubernetes_secret" "tls-rancher-ingress" {
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-rancher-ingress"
    namespace = kubernetes_namespace.rancher_cattle_system.metadata[0].name
  }
  data = {
    "tls.crt" = module.CSR.cert_pem
    "tls.key" = module.CSR.cert_key
  }
  type       = "kubernetes.io/tls"
  depends_on = [kubernetes_namespace.rancher_cattle_system]
}

resource "helm_release" "rancher" {
  depends_on = [kubernetes_secret.tls-ca, kubernetes_secret.tls-rancher-ingress, kubernetes_namespace.rancher_cattle_system]
  name       = "rancher"
  namespace  = "cattle-system"
  chart      = "rancher"
  repository = "https://releases.rancher.com/server-charts/latest/" // URL to your Helm chart repository
  #version          = "2.5.9"                                              // Specify the version of Rancher if needed
  #create_namespace = true
  max_history = 5

  set {
    name  = "hostname"
    value = var.hostname
  }

  set {
    name  = "replicas"
    value = "1"
  }
  set {
    name  = "bootstrapPassword"
    value = "rancherrancher"
  }
  set {
    name  = "ingress.tls.source"
    value = "secret"
  }
  set {
    name  = "privateCA"
    value = "true"
  }
}

#provider "rancher2" {
#alias     = "bootstrap"
#api_url   = "https://${var.hostname}"
#bootstrap = true
#insecure  = true
#}

resource "rancher2_bootstrap" "setup_admin" {
  # provider         = rancher2.bootstrap
  depends_on       = [helm_release.rancher]
  initial_password = "rancherrancher"
  password         = "administrator"
  telemetry        = true
}

output "token_key" {
  value = rancher2_bootstrap.setup_admin.token
}

#provider "rancher2" {
#alias     = "admin"
#api_url   = "https://${var.hostname}"
#token_key = rancher2_bootstrap.setup_admin.token
#insecure  = true
#}
