data "terraform_remote_state" "sample-lab" {
  backend = "local"
  config = {
    path = "../sample-lab/terraform.tfstate"
  }
}

locals {
  labdata        = data.terraform_remote_state.sample-lab.outputs
  minio_host     = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio"), "https://", ""), "/", "")
  minio_api_host = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio-api"), "https://", ""), "/", "")
  rancher_cluster_id = local.labdata.rancher_cluster_cluster_id
  sample0_cluster_id = local.labdata.sample_cluster_ids[0].id
  sample1_cluster_id = local.labdata.sample_cluster_ids[1].id
}

provider "rancher2" {
  api_url   = local.labdata.rancher_url
  token_key = local.labdata.rancher_token
  insecure  = true
}

provider "kubernetes" {
  alias                  = "rancher"
  host                   = local.labdata.rancher_cluster.endpoint
  client_certificate     = local.labdata.rancher_cluster.client_certificate
  client_key             = local.labdata.rancher_cluster.client_key
  cluster_ca_certificate = local.labdata.rancher_cluster.cluster_ca_certificate
}

provider "helm" {
  alias                  = "rancher"
  kubernetes  {
  host                   = local.labdata.sample_cluster_ids[0].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[0].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[0].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[0].cluster_data.cluster_ca_certificate
  }
}

provider "kubernetes" {
  alias                  = "upc-sample0"
  host                   = local.labdata.sample_cluster_ids[0].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[0].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[0].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[0].cluster_data.cluster_ca_certificate
}

provider "helm" {
  alias                  = "upc-sample0"
  kubernetes  {
  host                   = local.labdata.sample_cluster_ids[0].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[0].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[0].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[0].cluster_data.cluster_ca_certificate
  }
}

provider "kubernetes" {
  alias                  = "upc-sample1"
  host                   = local.labdata.sample_cluster_ids[1].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[1].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[1].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[1].cluster_data.cluster_ca_certificate
}

provider "helm" {
  alias                  = "upc-sample1"
  kubernetes  {
  host                   = local.labdata.sample_cluster_ids[1].cluster_data.endpoint
  client_certificate     = local.labdata.sample_cluster_ids[1].cluster_data.client_certificate
  client_key             = local.labdata.sample_cluster_ids[1].cluster_data.client_key
  cluster_ca_certificate = local.labdata.sample_cluster_ids[1].cluster_data.cluster_ca_certificate
  }
}

module "CSR-api" {
  source   = "../modules/CSR"
  dns-name = local.minio_api_host
  ca_key   = local.labdata.ca_cert-key
  ca_cert  = local.labdata.ca_cert-pem
}

module "CSR" {
  source   = "../modules/CSR"
  dns-name = local.minio_host
  ca_key   = local.labdata.ca_cert-key
  ca_cert  = local.labdata.ca_cert-pem
}


module "minio-setup" {
  providers = {
    kubernetes = kubernetes.rancher
  }
  source = "./modules/minio-install"
  minio_host = local.minio_host
  minio_api_host = local.minio_api_host
  CSR-api = module.CSR-api
  CSR = module.CSR
}


provider "minio" {
  minio_server   = module.minio-setup.minio_api_host
  minio_user     = "minioadmin"
  minio_password = "minioadmin"
  minio_ssl      = true
  minio_insecure = true
}

resource "minio_s3_bucket" "thanos" {
  bucket = "thanos"
  acl    = "public"
}

module "initialize_monitoring_rancher" {
  source = "./modules/cluster-prepare"
  cluster_id = local.rancher_cluster_id
  thanos_bucket = "thanos"
  thanos_s3_host = module.minio-setup.minio_api_host
  providers = {
    kubernetes = kubernetes.rancher
    helm = helm.rancher
    rancher2 = rancher2
  }
}


output "rancher_url" {
  value = local.labdata.rancher_url
}
output "minio_url" {
  value = "${module.minio-setup.minio_url}"
}

output "bucket_arn" {
  value = minio_s3_bucket.thanos.arn
}
output "bucket_domain" {
  value = minio_s3_bucket.thanos.bucket_domain_name
}

#output "data" {
#value = data.terraform_remote_state.sample-lab
#}
