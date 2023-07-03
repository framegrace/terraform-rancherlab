#module "clusters" {
#source = "../modules/clusters"
#}

locals {
  rancher_hostname = "${module.upc-rancher.docker-data-cp.IPAddress}.sslip.io"
}

module "upc-rancher" {
  source       = "../modules/cluster"
  cluster_name = "upc-rancher"
}

module "upc-sample1" {
  source       = "../modules/cluster"
  cluster_name = "upc-sample1"
  workers      = 1
}

module "upc-sample2" {
  source       = "../modules/cluster"
  cluster_name = "upc-sample2"
  workers      = 1
}

provider "kubernetes" {
  alias                  = "upc-rancher"
  host                   = module.upc-rancher.data.endpoint
  client_certificate     = module.upc-rancher.data.client_certificate
  client_key             = module.upc-rancher.data.client_key
  cluster_ca_certificate = module.upc-rancher.data.cluster_ca_certificate
}

provider "helm" {
  alias = "upc-rancher"
  kubernetes {
    host                   = module.upc-rancher.data.endpoint
    client_certificate     = module.upc-rancher.data.client_certificate
    client_key             = module.upc-rancher.data.client_key
    cluster_ca_certificate = module.upc-rancher.data.cluster_ca_certificate
  }
}

resource "helm_release" "cert-manager" {
  provider         = helm.upc-rancher
  depends_on       = [module.upc-rancher]
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


resource "null_resource" "kubectl_apply" {
  depends_on = [module.upc-rancher]
  provisioner "local-exec" {
    #command = "kubectl config use-context kind-upc-rancher && kubectl create namespace ingress-nginx && kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml"
    command = <<EOF
      kubectl config use-context kind-upc-rancher && \
      kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml && \
      sleep 15
      kubectl config use-context kind-upc-rancher && \
      kubectl wait --namespace ingress-nginx \
         --for=condition=ready pod \
         --selector=app.kubernetes.io/component=controller \
         --timeout=90s
EOF
  }
}

module "CA" {
  source = "../modules/CA"
}

resource "kubernetes_namespace" "rancher_cattle_system" {
  provider = kubernetes.upc-rancher
  lifecycle {
    ignore_changes = all
  }
  metadata {
    name = "cattle-system"
  }
  depends_on = [module.upc-rancher]
}

resource "kubernetes_secret" "tls-ca" {
  provider = kubernetes.upc-rancher
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-ca"
    namespace = "cattle-system"
  }
  data = {
    "cacerts.pem" = module.CA.ca-cert-pem
  }
  type       = "generic"
  depends_on = [kubernetes_namespace.rancher_cattle_system, module.CA]
}

module "CSR" {
  source   = "../modules/CSR"
  dns-name = local.rancher_hostname
  ca_key   = module.CA.ca-priv-key-pem
  ca_cert  = module.CA.ca-cert-pem
}

resource "kubernetes_secret" "tls-rancher-ingress" {
  provider   = kubernetes.upc-rancher
  depends_on = [kubernetes_namespace.rancher_cattle_system, module.CSR]
  lifecycle {
    ignore_changes = [metadata]
  }
  metadata {
    name      = "tls-rancher-ingress"
    namespace = "cattle-system"
  }
  data = {
    "tls.crt" = module.CSR.cert_pem
    "tls.key" = module.CSR.cert_key
  }
  type = "kubernetes.io/tls"
}

resource "helm_release" "rancher" {
  provider   = helm.upc-rancher
  depends_on = [null_resource.kubectl_apply, kubernetes_secret.tls-ca, kubernetes_secret.tls-rancher-ingress]
  name       = "rancher"
  namespace  = "cattle-system"
  chart      = "rancher"
  repository = "https://releases.rancher.com/server-charts/latest/" // URL to your Helm chart repository
  #version          = "2.5.9"                                              // Specify the version of Rancher if needed
  #create_namespace = true
  max_history = 5

  set {
    name  = "hostname"
    value = local.rancher_hostname
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

provider "rancher2" {
  alias     = "bootstrap"
  api_url   = "https://${local.rancher_hostname}"
  bootstrap = true
  insecure  = true
}

provider "rancher2" {
  alias     = "admin"
  api_url   = "https://${local.rancher_hostname}"
  token_key = rancher2_bootstrap.setup_admin.token
  insecure  = true
}

resource "rancher2_bootstrap" "setup_admin" {
  provider         = rancher2.bootstrap
  depends_on       = [helm_release.rancher]
  initial_password = "rancherrancher"
  password         = "administrator"
  telemetry        = true
}

provider "kubernetes" {
  alias                  = "upc-sample1"
  host                   = module.upc-sample1.data.endpoint
  client_certificate     = module.upc-sample1.data.client_certificate
  client_key             = module.upc-sample1.data.client_key
  cluster_ca_certificate = module.upc-sample1.data.cluster_ca_certificate
}
provider "kubernetes" {
  alias                  = "upc-sample2"
  host                   = module.upc-sample2.data.endpoint
  client_certificate     = module.upc-sample2.data.client_certificate
  client_key             = module.upc-sample2.data.client_key
  cluster_ca_certificate = module.upc-sample2.data.cluster_ca_certificate
}

module "import-sample1" {
  depends_on          = [rancher2_bootstrap.setup_admin, module.upc-sample1]
  source              = "../modules/importer"
  cluster-name        = "upc-sample1"
  cluster-description = "UPC Sample cluster 1"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes = kubernetes.upc-sample1
    rancher2   = rancher2.admin
  }
}

module "import-sample2" {
  depends_on          = [rancher2_bootstrap.setup_admin, module.upc-sample2]
  source              = "../modules/importer"
  cluster-name        = "upc-sample2"
  cluster-description = "UPC Sample cluster 2"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes = kubernetes.upc-sample2
    rancher2   = rancher2.admin
  }
}

output "rancher_url" {
  value = "https://${local.rancher_hostname}/"
}
