#module "clusters" {
#source = "../modules/clusters"
#}

module "test-sample1" {
  source        = "../modules/cluster"
  cluster_name  = "test-sample1"
  port_mappings = []
}

module "test-sample2" {
  source        = "../modules/cluster"
  cluster_name  = "test-sample2"
  port_mappings = []
}
