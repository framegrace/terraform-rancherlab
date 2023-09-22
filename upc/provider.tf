terraform {
  required_providers {
    #    kind = {
    #  source  = "tehcyx/kind"
    #  version = "0.2.0"
    #}
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.21.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.10.1"
    }
    #tls = {
    #  source  = "hashicorp/tls"
    #  version = "4.0.4"
    #}
    rancher2 = {
      source  = "rancher/rancher2"
      version = "3.0.2"
    }
    minio = {
      source  = "aminueza/minio"
      version = "1.18.0"
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
