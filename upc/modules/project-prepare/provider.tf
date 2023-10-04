terraform {
  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "3.0.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.21.1"
    }
  }
}

#provider "rancher2" {
#  # Configuration options
#  api_url = "http://${local.rancher_hostname}"
#}
#provider "kind" {
#  # Configuration options
#}
#provider "tls" {
#  # Configuration options
#}
