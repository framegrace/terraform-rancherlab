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
  #depends_on = [ module.minio-setup ]
  source = "./modules/cluster-prepare"
  cluster_id = local.rancher_cluster_id
  thanos_bucket = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.rancher
    helm = helm.rancher
    rancher2 = rancher2
  }
}

module "initialize_monitoring_sample0" {
  #  depends_on = [ module.minio-setup ]
  source = "./modules/cluster-prepare"
  cluster_id = local.sample0_cluster_id
  thanos_bucket = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.upc-sample0
    helm = helm.upc-sample0
    rancher2 = rancher2
  }
}

module "initialize_monitoring_sample1" {
  #depends_on = [ module.minio-setup ]
  source = "./modules/cluster-prepare"
  cluster_id = local.sample1_cluster_id
  thanos_bucket = "thanos"
  thanos_s3_host = ""
  providers = {
    kubernetes = kubernetes.upc-sample1
    helm = helm.upc-sample1
    rancher2 = rancher2
  }
}

resource "rancher2_project" "sampleproject0" {
  depends_on = [ module.initialize_monitoring_sample0 ]
  name = "sampleproject"
  cluster_id = local.sample0_cluster_id
 enable_project_monitoring = true
# project_monitoring_input {
#   answers = {
#   "alertmanager.enabled" = true
#   "federate.enabled" = true
#   "grafana.adminPassword" = "admin"
#   "grafana.adminUser" = "admin"
#   "grafana.enabled" = true
#   "grafana.persistence.accessModes[0]" = "ReadWriteOnce"
#   "grafana.persistence.enabled" = true
#   "grafana.persistence.size" = "1Gi"
#   "grafana.persistence.storageClass" = "standard"
#   "grafana.sidecar.dashboards.label" = "grafana_dashboard"
#   "prometheus.prometheusSpec.evaluationInterval" = "1m"
#   "prometheus.prometheusSpec.resources.limits.cpu" = "1000m"
#   "prometheus.prometheusSpec.resources.limits.memory" = "3000Mi"
#   "prometheus.prometheusSpec.resources.requests.cpu" = "750m"
#   "prometheus.prometheusSpec.resources.requests.memory" = "750Mi"
#   "prometheus.prometheusSpec.retention" = "10d"
#   "prometheus.prometheusSpec.retentionSize" = "50GB"
#   "prometheus.prometheusSpec.scrapeInterval" = "30s"
#   }
# }
  resource_quota {
    project_limit {
      limits_cpu = "6000m"
      limits_memory = "15000Mi"
      requests_storage = "10Gi"
    }
    namespace_default_limit {
      limits_cpu = "1200m"
      limits_memory = "1500Mi"
      requests_storage = "200Mi"
    }
  }
  container_resource_limit {
    limits_cpu = "2000m"
    limits_memory = "500Mi"
    requests_cpu = "1000m"
    requests_memory = "100Mi"
  }
}

resource "rancher2_namespace" "namespace-zero" {
  name = "zero"
  project_id = rancher2_project.sampleproject0.id
  #resource_quota {
    #limit {
      #limits_cpu = "100m"
      #limits_memory = "100Mi"
      #requests_storage = "10Mi"
    #}
  #}
}

#module "stresser-sample-zero" {
#  depends_on = [ rancher2_namespace.namespace-zero ]
#  source = "./modules/stresser"
#  namespace = "zero"
#  replica_count = 1
#  name = "behaver"
#  stress_cpu = 1
#  stress_vm = 1
#  providers = {
#    kubernetes = kubernetes.upc-sample0
#  }
#}

resource "rancher2_namespace" "namespace-cero" {
  depends_on = [ rancher2_namespace.namespace-cero ]
  name = "cero"
  project_id = rancher2_project.sampleproject0.id
  resource_quota {
    limit {
      limits_cpu = "1000m"
      limits_memory = "1500Mi"
      requests_storage = "1Gi"
    }
  }
}

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

resource "rancher2_project" "otherproject" {
  depends_on = [ module.initialize_monitoring_sample1 ]
  name = "otherproject"
  cluster_id = local.sample1_cluster_id
  enable_project_monitoring = true
  resource_quota {
    project_limit {
      limits_cpu = "10000m"
      limits_memory = "20000Mi"
      requests_storage = "20Gi"
    }
    namespace_default_limit {
      limits_cpu = "2200m"
      limits_memory = "4000Mi"
      requests_storage = "500Mi"
    }
  }
  container_resource_limit {
    limits_cpu = "2000m"
    limits_memory = "500Mi"
    requests_cpu = "1000m"
    requests_memory = "100Mi"
  }
}

resource "rancher2_namespace" "namespace-other" {
  name = "other"
  project_id = rancher2_project.otherproject.id
}

#module "stresser-sample-other" {
  #depends_on = [ rancher2_namespace.namespace-other ]
  #source = "./modules/stresser"
  #namespace = "other"
  #replica_count = 1
  #name = "cpu-hitter"
  #stress_cpu = 4
  #stress_vm = 1
  #providers = {
    #kubernetes = kubernetes.upc-sample1
  #}
#}
#
resource "rancher2_namespace" "namespace-altre" {
  name = "altre"
  project_id = rancher2_project.otherproject.id
  resource_quota {
    limit {
      limits_cpu = "1000m"
      limits_memory = "1000Mi"
      requests_storage = "10Mi"
    }
  }
}

#module "stresser-sample-altre" {
  #depends_on = [ rancher2_namespace.namespace-altre ]
  #source = "./modules/stresser"
  #namespace = "altre"
  #replica_count = 2
  #name = "replicator"
  #cpu_limit = "300m"
  #stress_cpu = 1
  #stress_vm = 1
  #providers = {
    #kubernetes = kubernetes.upc-sample1
  #}
#}
#
resource "rancher2_project" "testproject0" {
  depends_on = [ module.initialize_monitoring_sample0 ]
  name = "testproject"
  cluster_id = local.sample0_cluster_id
  enable_project_monitoring = true
  resource_quota {
    project_limit {
      limits_cpu = "8000m"
      limits_memory = "20000Mi"
      requests_storage = "20Gi"
    }
    namespace_default_limit {
      limits_cpu = "1200m"
      limits_memory = "2000Mi"
      requests_storage = "300Mi"
    }
  }
  container_resource_limit {
    limits_cpu = "2000m"
    limits_memory = "500Mi"
    requests_cpu = "1000m"
    requests_memory = "100Mi"
  }
}

resource "rancher2_namespace" "namespace-test-o" {
  name = "test-o"
  project_id = rancher2_project.testproject0.id
}

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
resource "rancher2_namespace" "namespace-test-a" {
  name = "test-a"
  project_id = rancher2_project.testproject0.id
}

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
      #limits_cpu = "100m"
      #limits_memory = "100Mi"
      #requests_storage = "1Gi"
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


resource "rancher2_project" "testproject1" {
  depends_on = [ module.initialize_monitoring_sample1 ]
  name = "testproject"
  cluster_id = local.sample1_cluster_id
  enable_project_monitoring = true
  resource_quota {
    project_limit {
      limits_cpu = "2000m"
      limits_memory = "2000Mi"
      requests_storage = "2Gi"
    }
    namespace_default_limit {
      limits_cpu = "2000m"
      limits_memory = "500Mi"
      requests_storage = "1Gi"
    }
  }
  container_resource_limit {
    limits_cpu = "500m"
    limits_memory = "100Mi"
    requests_cpu = "100m"
    requests_memory = "50Mi"
  }
}

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
#output "minio_url" {
#value = "${module.minio-setup.minio_url}"
#}

#output "bucket_arn" {
#value = minio_s3_bucket.thanos.arn
#}
#output "bucket_domain" {
#value = minio_s3_bucket.thanos.bucket_domain_name
#}

#output "data" {
#value = data.terraform_remote_state.sample-lab
#}
