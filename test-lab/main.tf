#module "clusters" {
#source = "../modules/clusters"
#}

module "test-sample1" {
  source       = "../modules/cluster"
  cluster_name = "test-sample1"
  workers      = 2
}
#
#module "test-sample2" {
#source        = "../modules/cluster"
#cluster_name  = "test-sample2"
#port_mappings = []
##   {
##     container_port = 80
##     host_port      = 80
##     listen_address = "192.168.1.103"
##   },
##   {
##     container_port = 443
##     host_port      = 443
##     listen_address = "192.168.1.103"
##   }
## ]
#}
#
#output "kubeconfig" {
#value = module.test-sample1.data.kubeconfig
#}
#output "local_IP" {
#value = module.test-sample1.docker-data.NetworkSettings.Networks.kind.IPAddress
#}

#output "data" {
#value = kind_cluster.k8s_cluster
#}
output "docker-data" {
  value = module.test-sample1.docker-data-cp
}
output "docker-data-w" {
  value = module.test-sample1.docker-data-wrk
}
