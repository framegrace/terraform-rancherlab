variable "cluster_name" {
  type = string
}

variable "node_image" {
  type    = string
  default = "kindest/node:v1.26.6@sha256:6e2d8b28a5b601defe327b98bd1c2d1930b49e5d8c512e1895099e4504007adb"
}

variable "port_mappings" {
  type = list(object({
    container_port = number
    host_port      = number
  }))
}

resource "kind_cluster" "k8s_cluster" {
  name       = var.cluster_name
  node_image = var.node_image
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
        }
      }
    }
  }
}
#
output "data" {
  value = kind_cluster.k8s_cluster
}
