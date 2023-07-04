variable "cluster_name" {
  type = string
}

variable "workers" {
  type    = number
  default = 0
}

variable "nginx_ingress" {
  type    = bool
  default = true
}

variable "node_image" {
  type    = string
  default = "kindest/node:v1.26.6@sha256:6e2d8b28a5b601defe327b98bd1c2d1930b49e5d8c512e1895099e4504007adb"
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
    }
    dynamic "node" {
      for_each = range(var.workers)
      content {
        role = "worker"
        #kubeadm_config_patches = [
        #  "kind: JoinConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
        #]
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.k8s_cluster.endpoint
  client_certificate     = kind_cluster.k8s_cluster.client_certificate
  client_key             = kind_cluster.k8s_cluster.client_key
  cluster_ca_certificate = kind_cluster.k8s_cluster.cluster_ca_certificate
}

resource "null_resource" "kubectl_apply" {
  count      = var.nginx_ingress ? 1 : 0
  depends_on = [kind_cluster.k8s_cluster]
  provisioner "local-exec" {
    #command = "kubectl config use-context kind-upc-rancher && kubectl create namespace ingress-nginx && kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml"
    command = <<EOF
      kubectl config use-context kind-upc-rancher && \
      kubectl apply -n ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml && \
      sleep 20
      kubectl config use-context kind-upc-rancher && \
      kubectl wait --namespace ingress-nginx \
         --for=condition=ready pod \
         --selector=app.kubernetes.io/component=controller \
         --timeout=90s
EOF
  }
}
#
data "external" "docker-cp" {
  depends_on = [kind_cluster.k8s_cluster]
  program    = ["bash", "-c", "docker inspect ${var.cluster_name}-control-plane|jq -r '.[0].NetworkSettings.Networks.kind | {\"IPAddress\": .IPAddress, \"GlobalIPv6Address\": .GlobalIPv6Address}'"]
}
data "external" "docker-wrk" {
  depends_on = [kind_cluster.k8s_cluster]
  count      = var.workers
  program    = ["bash", "-c", "docker inspect ${var.cluster_name}-worker${count.index == 0 ? "" : count.index + 1}|jq -r '.[0].NetworkSettings.Networks.kind | {\"IPAddress\": .IPAddress, \"GlobalIPv6Address\": .GlobalIPv6Address}'"]
}
output "data" {
  value = kind_cluster.k8s_cluster
}
output "docker-data-cp" {
  value = data.external.docker-cp.result
}
output "docker-data-wrk" {
  value = data.external.docker-wrk.*.result
}
