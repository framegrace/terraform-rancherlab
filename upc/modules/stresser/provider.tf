terraform {
  required_providers {
    #kubernetes = {
    #  source  = "hashicorp/kubernetes"
    #  version = "2.21.1"
    #}
    rancher2 = {
      source  = "rancher/rancher2"
      version = "3.0.2"
    }
  }
}
