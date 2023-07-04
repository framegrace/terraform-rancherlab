terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.21.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.10.1"
    }
    #    tls = {
    #  source  = "hashicorp/tls"
    #  version = "4.0.4"
    #}
    rancher2 = {
      source  = "rancher/rancher2"
      version = "3.0.2"
    }
  }
}

#provider "kind" {
## Configuration options
#}
#provider "tls" {
## Configuration options
#}
