#module "clusters" {
#source = "../modules/clusters"
#}
variable "clusters" {
  type    = number
  default = 2
}

variable "nodes_per_cluster" {
  type    = number
  default = 1
}

locals {
  rancher_hostname = "${module.upc-rancher.docker-data-cp.IPAddress}.sslip.io"
}

module "upc-rancher" {
  source       = "../modules/cluster"
  cluster_name = "upc-rancher"
}

module "upc-samples" {
  count         = var.clusters
  source        = "../modules/cluster"
  cluster_name  = "upc-sample-${count.index}"
  workers       = var.nodes_per_cluster
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

module "imported-clusters" {
  count               = length(module.upc-samples)
  depends_on          = [module.rancher-server, module.upc-sample1]
  cluster             = module.upc-samples[count.index]
  source              = "../modules/importer"
  cluster-name        = "upc-sample${count.index}"
  cluster-description = "UPC Sample cluster ${count.index}"
  ca-cert-pem         = module.CA.ca-cert-pem
}

# Add stuff to the servers using the provider and the cluster_id
resource "rancher2_app_v2" "rancher-monitoring" {
  count      = length(module.upc-samples)
  cluster_id = module.imported-clusters[count.index].cluster_id
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  #chart_version = "9.4.200"
  #values = file("values.yaml")
}

output "rancher_url" {
  value = "https://${local.rancher_hostname}/"
}
