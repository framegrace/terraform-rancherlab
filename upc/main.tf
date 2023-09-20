variable "customers" {
  description = "Information about customers, their projects, and namespaces"
  type = list(object({
    customer_name     = string
    customer_password = string
    projects = list(object({
      project_name     = string
      cluster_id       = number
      resource_profile = number
      namespaces = list(object({
        namespace_name   = string
        resource_profile = number
        stresser         = string
      }))
    }))
  }))
  default = [
    {
      customer_name     = "Winter"
      customer_password = "snowflake12345"
      projects = [
        {
          project_name     = "December"
          cluster_id       = 0
          resource_profile = 2
          namespaces = [
            {
              namespace_name   = "Snow"
              resource_profile = 2
              stresser         = "memory"
            },
            {
              namespace_name   = "Christmas"
              resource_profile = 2
              stresser         = "cpu"
            }
          ]
        },
        {
          project_name     = "January"
          cluster_id       = 1
          resource_profile = 2
          namespaces = [
            {
              namespace_name   = "Ice"
              resource_profile = 2
              stresser         = "replica"
            },
            {
              namespace_name   = "NewYear"
              resource_profile = 2
              stresser         = "behaver"
            }
          ]
        }
      ]
    },
    {
      customer_name     = "Spring"
      customer_password = "springblossom456"
      projects = [
        {
          project_name     = "April"
          cluster_id       = 1
          resource_profile = 1
          namespaces = [
            {
              namespace_name   = "Rain"
              resource_profile = 1
              stresser         = "memory"
            },
            {
              namespace_name   = "Easter"
              resource_profile = 1
              stresser         = "cpu"
            }
          ]
        },
        {
          project_name     = "May"
          cluster_id       = 1
          resource_profile = 0
          namespaces = [
            {
              namespace_name   = "Flowers"
              resource_profile = 0
              stresser         = "memory"
            }
          ]
        }
      ]
    },
    {
      customer_name     = "Summer"
      customer_password = "sunshine789101"
      projects = [
        {
          project_name     = "July"
          cluster_id       = 0
          resource_profile = 0
          namespaces = [
            {
              namespace_name   = "Sun"
              resource_profile = 0
              stresser         = "replica"
            },
            {
              namespace_name   = "IndependenceDay"
              resource_profile = 0
              stresser         = "behaver"
            }
          ]
        }
      ]
    }
  ]
}

variable "resource_profile" {
  type = list(object({
    resource_quota = object({
      project_limit = object({
        limits_cpu       = string
        limits_memory    = string
        requests_storage = string
      })
      namespace_default_limit = object({
        limits_cpu       = string
        limits_memory    = string
        requests_storage = string
      })
    })
    container_resource_limit = object({
      limits_cpu      = string
      limits_memory   = string
      requests_cpu    = string
      requests_memory = string
    })
    namespace_limit = object({
      limits_cpu       = string
      limits_memory    = string
      requests_storage = string
    })
  }))
  default = [
    {
      resource_quota = {
        project_limit = {
          limits_cpu       = "6000m"
          limits_memory    = "15000Mi"
          requests_storage = "10Gi"
        }
        namespace_default_limit = {
          limits_cpu       = "1200m"
          limits_memory    = "1500Mi"
          requests_storage = "200Mi"
        }
      }
      container_resource_limit = {
        limits_cpu      = "2000m"
        limits_memory   = "500Mi"
        requests_cpu    = "1000m"
        requests_memory = "100Mi"
      }
      namespace_limit = {
        limits_cpu       = "1000m"
        limits_memory    = "1500Mi"
        requests_storage = "1Gi"
      }
    },
    {
      resource_quota = {
        project_limit = {
          limits_cpu       = "10000m"
          limits_memory    = "20000Mi"
          requests_storage = "20Gi"
        }
        namespace_default_limit = {
          limits_cpu       = "2200m"
          limits_memory    = "4000Mi"
          requests_storage = "500Mi"
        }
      }
      container_resource_limit = {
        limits_cpu      = "2000m"
        limits_memory   = "500Mi"
        requests_cpu    = "1000m"
        requests_memory = "100Mi"
      }
      namespace_limit = {
        limits_cpu       = "1000m"
        limits_memory    = "1000Mi"
        requests_storage = "10Mi"
      }
    },
    {
      resource_quota = {
        project_limit = {
          limits_cpu       = "8000m"
          limits_memory    = "20000Mi"
          requests_storage = "20Gi"
        }
        namespace_default_limit = {
          limits_cpu       = "1200m"
          limits_memory    = "2000Mi"
          requests_storage = "300Mi"
        }
      }
      container_resource_limit = {
        limits_cpu      = "2000m"
        limits_memory   = "500Mi"
        requests_cpu    = "1000m"
        requests_memory = "100Mi"
      }
      namespace_limit = {
        limits_cpu       = "100m"
        limits_memory    = "100Mi"
        requests_storage = "1Gi"
      }
    },
    {
      resource_quota = {
        project_limit = {
          limits_cpu       = "2000m"
          limits_memory    = "2000Mi"
          requests_storage = "2Gi"
        }
        namespace_default_limit = {
          limits_cpu       = "2000m"
          limits_memory    = "500Mi"
          requests_storage = "1Gi"
        }
      }
      container_resource_limit = {
        limits_cpu      = "500m"
        limits_memory   = "100Mi"
        requests_cpu    = "100m"
        requests_memory = "50Mi"
      }
      namespace_limit = {
        limits_cpu       = "100m"
        limits_memory    = "100Mi"
        requests_storage = "1Gi"
      }
    }
  ]
}

data "terraform_remote_state" "sample-lab" {
  backend = "local"
  config = {
    path = "../sample-lab/terraform.tfstate"
  }
}

locals {
  labdata            = data.terraform_remote_state.sample-lab.outputs
  minio_host         = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio"), "https://", ""), "/", "")
  minio_api_host     = replace(replace(replace(local.labdata.rancher_url, "rancher", "minio-api"), "https://", ""), "/", "")
  rancher_cluster_id = local.labdata.rancher_cluster_cluster_id
  sample0_cluster_id = module.imported-cluster0.cluster_id
  sample1_cluster_id = module.imported-cluster1.cluster_id
  clusters           = [ local.sample0_cluster_id,  local.sample1_cluster_id]
  flattened_projects = flatten([
    for customer in var.customers : [
      for project in customer.projects : {
        user_id          = rancher2_user.customer_user[customer.customer_name].id
        customer_name    = customer.customer_name
        project_name     = project.project_name
        resource_profile = project.resource_profile
        cluster_id       = local.clusters[project.cluster_id]
      }
    ]
  ])

  flattened_namespaces = flatten([
    for customer in var.customers : [
      for project in customer.projects : [
        for namespace in project.namespaces : {
          customer_name    = customer.customer_name
          project_name     = project.project_name
          cluster_id       = project.cluster_id
          namespace_name   = namespace.namespace_name
          resource_profile = namespace.resource_profile
          stresser         = namespace.stresser
        }
      ]
    ]
  ])
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
  alias = "rancher"
  kubernetes {
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
  alias = "upc-sample0"
  kubernetes {
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
  alias = "upc-sample1"
  kubernetes {
    host                   = local.labdata.sample_cluster_ids[1].cluster_data.endpoint
    client_certificate     = local.labdata.sample_cluster_ids[1].cluster_data.client_certificate
    client_key             = local.labdata.sample_cluster_ids[1].cluster_data.client_key
    cluster_ca_certificate = local.labdata.sample_cluster_ids[1].cluster_data.cluster_ca_certificate
  }
}

module "imported-cluster0" {
  source              = "../modules/importer"
  cluster-name        = "upc-sample0"
  cluster-description = "UPC Sample cluster 0"
  ca-cert-pem         = local.labdata.ca_cert-pem
  providers = {
    kubernetes : kubernetes.upc-sample0
    helm : helm.upc-sample0
    rancher2 : rancher2
  }
}

module "imported-cluster1" {
  source              = "../modules/importer"
  cluster-name        = "upc-sample1"
  cluster-description = "UPC Sample cluster 1"
  ca-cert-pem         = local.labdata.ca_cert-pem
  providers = {
    kubernetes : kubernetes.upc-sample1
    helm : helm.upc-sample1
    rancher2 : rancher2
  }
}

#resource "rancher2_cluster_sync" "wait-sync-0" {
#provider   = rancher2.admin
#  cluster_id = module.imported-cluster0.cluster_id
#}
#resource "rancher2_cluster_sync" "wait-sync-1" {
#  #provider   = rancher2.admin
#  cluster_id = module.imported-cluster1.cluster_id
#}

module "CSR-api" {
  source   = "../modules/CSR"
  dns-name = local.minio_api_host
  ca_key   = local.labdata.ca_cert-key
  ca_cert  = local.labdata.ca_cert-pem
}
#
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
  source         = "./modules/minio-install"
  minio_host     = local.minio_host
  minio_api_host = local.minio_api_host
  CSR-api        = module.CSR-api
  CSR            = module.CSR
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
  #depends_on = [ module.minio-setup ]
  source         = "./modules/cluster-prepare"
  cluster_id     = local.rancher_cluster_id
  minio_api_host = local.minio_api_host
  thanos_bucket  = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.rancher
    helm       = helm.rancher
    rancher2   = rancher2
  }
}

module "initialize_monitoring_sample0" {
  depends_on     = [module.imported-cluster0]
  source         = "./modules/cluster-prepare"
  cluster_id     = local.sample0_cluster_id
  minio_api_host = local.minio_api_host
  thanos_bucket  = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.upc-sample0
    helm       = helm.upc-sample0
    rancher2   = rancher2
  }
}

module "initialize_monitoring_sample1" {
  #depends_on = [ module.minio-setup ]
  depends_on     = [module.imported-cluster1]
  source         = "./modules/cluster-prepare"
  cluster_id     = local.sample1_cluster_id
  minio_api_host = local.minio_api_host
  thanos_bucket  = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.upc-sample1
    helm       = helm.upc-sample1
    rancher2   = rancher2
  }
}

# Create customers as Rancher users
resource "rancher2_user" "customer_user" {
  for_each = { for customer in var.customers : customer.customer_name => customer }

  username = each.value.customer_name
  password = each.value.customer_password
  name     = each.value.customer_name
  enabled  = true
}

resource "rancher2_global_role_binding" "global_restricted_admin" {
  for_each = { for customer in var.customers : customer.customer_name => customer }
  name             = lower("${each.value.customer_name}-global-restricted-admin")
  global_role_id = "restricted-admin"
  user_id          = rancher2_user.customer_user[each.value.customer_name].id
}

module "create_projects" {
  depends_on = [module.initialize_monitoring_sample0,
  module.initialize_monitoring_sample1]
  source                    = "./modules/project-prepare"
  for_each                  = { for proj in local.flattened_projects : lower("${proj.customer_name}-${proj.project_name}") => proj }
  project_name              = each.value.project_name
  cluster_id                = each.value.cluster_id
  owner_user_id             = each.value.user_id
  enable_project_monitoring = true
  resource_quota            = var.resource_profile[each.value.resource_profile].resource_quota
  container_resource_limit  = var.resource_profile[each.value.resource_profile].container_resource_limit
}

resource "rancher2_namespace" "namespaces" {
  depends_on = [module.create_projects]
  for_each   = { for ns in local.flattened_namespaces : lower("${ns.customer_name}-${ns.project_name}-${ns.namespace_name}") => ns }

  name       = lower(each.value.namespace_name)
  project_id = module.create_projects[lower("${each.value.customer_name}-${each.value.project_name}")].project_id
  resource_quota {
    limit {
      limits_cpu       = var.resource_profile[each.value.resource_profile].namespace_limit.limits_cpu
      limits_memory    = var.resource_profile[each.value.resource_profile].namespace_limit.limits_memory
      requests_storage = var.resource_profile[each.value.resource_profile].namespace_limit.requests_storage
    }
  }
}

#module "stresser-sample-zero" {
#depends_on    = [rancher2_namespace.namespaces]
#for_each = { for ns in local.flattened_namespaces : "${ns.customer_name}-${ns.project_name}-${ns.namespace_name}" => ns }
#source        = "./modules/stresser"
#namespace     = each.value.namespace_name
#replica_count = 1
#name          = each.value.stresser
#stress_cpu    = 1
#stress_vm     = 1
#providers = {
#kubernetes = kubernetes.upc-sample0
#}
#}

#module "stresser-sample-cero" {
#depends_on = [ rancher2_namespace.namespace-cero ]
#source = "./modules/stresser"
#namespace = "cero"
#replica_count = 1
#name = "mem-hitter"
#stress_cpu = 1
#stress_vm = 2
#memory_limit = "800M"
#providers = {
#kubernetes = kubernetes.upc-sample0
#}
#}


#module "stresser-sample-test-o" {
#depends_on = [ rancher2_namespace.namespace-test-o ]
#source = "./modules/stresser"
#namespace = "test-o"
#replica_count = 1
#name = "cpu-hitter"
#stress_cpu = 4
#stress_vm = 1
#providers = {
#kubernetes = kubernetes.upc-sample0
#}
#}
#
#module "stresser-sample-test-a" {
#depends_on = [ rancher2_namespace.namespace-test-a ]
#source = "./modules/stresser"
#namespace = "test-a"
#replica_count = 2
#name = "replicator"
#cpu_limit = "300m"
#stress_cpu = 1
#stress_vm = 1
#providers = {
#kubernetes = kubernetes.upc-sample0
#}
#}
#
#resource "rancher2_namespace" "namespace-test-cero" {
#name = "foo"
#project_id = rancher2_project.testproject0.id
#resource_quota {
#limit {
#}
#}
#}

#resource "rancher2_namespace" "namespace-test-zero" {
#name = "foo"
#project_id = rancher2_project.testproject0.id
#resource_quota {
#limit {
#limits_cpu = "100m"
#limits_memory = "100Mi"
#requests_storage = "1Gi"
#}
#}
#}


#resource "rancher2_namespace" "namespace-test-one" {
#name = "foo"
#project_id = rancher2_project.testproject1.id
#resource_quota {
#limit {
#limits_cpu = "100m"
#limits_memory = "100Mi"
#requests_storage = "1Gi"
#}
#}
#}
#
#resource "rancher2_namespace" "namespace-test-uno" {
#name = "foo"
#project_id = rancher2_project.testproject1.id
#resource_quota {
#limit {
#limits_cpu = "100m"
#limits_memory = "100Mi"
#requests_storage = "1Gi"
#}
#}
#}


output "rancher_url" {
  value = local.labdata.rancher_url
}
output "minio_url" {
  value = module.minio-setup.minio_url
}

output "bucket_arn" {
  value = minio_s3_bucket.thanos.arn
}
output "bucket_domain" {
  value = minio_s3_bucket.thanos.bucket_domain_name
}

output "projects" {
value = local.flattened_projects
}
