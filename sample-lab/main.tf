#module "clusters" {
#source = "../modules/clusters"
#}
variable "nodes_per_cluster" {
  type    = number
  default = 1
}

variable "storage" {
  type    = string
  default = "storage"
}

locals {
  rancher_hostname = "rancher-${module.upc-rancher.docker-data-cp.IPAddress}.sslip.io"
}

module "upc-rancher" {
  source       = "../modules/cluster"
  cluster_name = "upc-rancher"
  storagePath  = "${path.module}/${var.storage}"
}

module "upc-sample0" {
  source       = "../modules/cluster"
  cluster_name = "upc-sample-0"
  workers      = var.nodes_per_cluster
  storagePath  = "${path.module}/${var.storage}"
}
module "upc-sample1" {
  source       = "../modules/cluster"
  cluster_name = "upc-sample-1"
  workers      = var.nodes_per_cluster
  storagePath  = "${path.module}/${var.storage}"
}

module "CA" {
  source = "../modules/CA"
}

# Prepare providers for rancher server
provider "kubernetes" {
  alias                  = "rancher"
  host                   = module.upc-rancher.data.endpoint
  client_certificate     = module.upc-rancher.data.client_certificate
  client_key             = module.upc-rancher.data.client_key
  cluster_ca_certificate = module.upc-rancher.data.cluster_ca_certificate
}

provider "helm" {
  alias = "rancher"
  kubernetes {
    host                   = module.upc-rancher.data.endpoint
    client_certificate     = module.upc-rancher.data.client_certificate
    client_key             = module.upc-rancher.data.client_key
    cluster_ca_certificate = module.upc-rancher.data.cluster_ca_certificate
  }
}

provider "rancher2" {
  alias     = "bootstrap"
  api_url   = "https://${local.rancher_hostname}"
  bootstrap = true
  insecure  = true
}

module "rancher-server" {
  depends_on = [module.upc-rancher]
  source     = "../modules/rancher"
  hostname   = local.rancher_hostname
  CA         = module.CA
  providers = {
    kubernetes = kubernetes.rancher
    helm       = helm.rancher
    rancher2   = rancher2.bootstrap
  }
}

provider "rancher2" {
  #alias     = "admin"
  api_url   = "https://${local.rancher_hostname}"
  token_key = module.rancher-server.token_key
  # Would need to add the CA to the local system
  # for this to be secure. Will investigate if theres
  # any way.
  insecure = true
}

provider "kubernetes" {
  alias                  = "upc-sample0"
  host                   = module.upc-sample0.data.endpoint
  client_certificate     = module.upc-sample0.data.client_certificate
  client_key             = module.upc-sample0.data.client_key
  cluster_ca_certificate = module.upc-sample0.data.cluster_ca_certificate

}
provider "kubernetes" {
  alias                  = "upc-sample1"
  host                   = module.upc-sample1.data.endpoint
  client_certificate     = module.upc-sample1.data.client_certificate
  client_key             = module.upc-sample1.data.client_key
  cluster_ca_certificate = module.upc-sample1.data.cluster_ca_certificate
}

module "imported-cluster0" {
  depends_on          = [module.rancher-server, module.upc-sample0]
  source              = "../modules/importer"
  cluster-name        = "upc-sample0"
  cluster-description = "UPC Sample cluster 0"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes : kubernetes.upc-sample0
    #rancher2 : rancher2.admin
    rancher2 : rancher2
  }
}

module "imported-cluster1" {
  depends_on          = [module.rancher-server, module.upc-sample1]
  source              = "../modules/importer"
  cluster-name        = "upc-sample1"
  cluster-description = "UPC Sample cluster 1"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes : kubernetes.upc-sample1
    #rancher2 : rancher2.admin
    rancher2 : rancher2
  }
}

resource "rancher2_cluster_sync" "wait-sync-0" {
  #provider   = rancher2.admin
  cluster_id = module.imported-cluster0.cluster_id
}
resource "rancher2_cluster_sync" "wait-sync-1" {
  #provider   = rancher2.admin
  cluster_id = module.imported-cluster1.cluster_id
}
data "rancher2_cluster" "local-cluster" {
  depends_on = [module.rancher-server]
  name       = "local"
}

output "rancher_url" {
  value = "https://${local.rancher_hostname}/"
}
output "rancher_token" {
  value     = module.rancher-server.token_key
  sensitive = true
}
output "rancher_cluster" {
  value = module.upc-rancher.data
}
output "rancher_cluster_cluster_id" {
  value = data.rancher2_cluster.local-cluster.id
}
output "sample_cluster_ids" {
  value = [{
    name         = "upc-sample0",
    IP           = module.upc-sample0.docker-data-cp.IPAddress,
    id           = module.imported-cluster0.cluster_id,
    cluster_data = module.upc-sample0.data
    }, {
    name         = "upc-sample1",
    IP           = module.upc-sample0.docker-data-cp.IPAddress,
    id           = module.imported-cluster1.cluster_id,
    cluster_data = module.upc-sample1.data
  }]
}
output "ca_cert-pem" {
  value = module.CA.ca-cert-pem
}
output "ca_cert-key" {
  value     = module.CA.ca-priv-key-pem
  sensitive = true
}
