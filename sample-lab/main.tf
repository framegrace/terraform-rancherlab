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
  source        = "../modules/cluster"
  cluster_name  = "upc-sample1"
  workers       = 1
  nginx_ingress = false
}

module "upc-sample2" {
  source        = "../modules/cluster"
  cluster_name  = "upc-sample2"
  workers       = 1
  nginx_ingress = false
}

module "CA" {
  source = "../modules/CA"
}

module "rancher-server" {
  source   = "../modules/rancher"
  hostname = local.rancher_hostname
  CA       = module.CA
  cluster  = module.upc-rancher.data
}

provider "rancher2" {
  api_url   = "https://${local.rancher_hostname}"
  token_key = module.rancher-server.token_key
  # Would need to add the CA to the local system
  # for this to be secure. Will investigate if theres
  # any way.
  insecure = true
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
  depends_on          = [module.rancher-server, module.upc-sample1]
  source              = "../modules/importer"
  cluster-name        = "upc-sample1"
  cluster-description = "UPC Sample cluster 1"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes = kubernetes.upc-sample1
    #rancher2   = rancher2.admin
  }
}

module "import-sample2" {
  depends_on          = [module.rancher-server, module.upc-sample2]
  source              = "../modules/importer"
  cluster-name        = "upc-sample2"
  cluster-description = "UPC Sample cluster 2"
  ca-cert-pem         = module.CA.ca-cert-pem
  providers = {
    kubernetes = kubernetes.upc-sample2
    #rancher2   = rancher2.admin
  }
}

output "rancher_url" {
  value = "https://${local.rancher_hostname}/"
}
