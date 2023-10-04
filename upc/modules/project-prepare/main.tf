# Name of the project
variable "project_name" {
  description = "The name of the Rancher project"
  type        = string
}

# Cluster ID where the project resides
variable "cluster_id" {
  description = "The ID of the cluster where the project will be created"
  type        = string
}
# User ID of the project owner
variable "owner_user_id" {
  description = "The user ID of the project owner"
  type        = string
}
variable "owner" {
  type = string
}
# Enable or disable project monitoring
variable "enable_project_monitoring" {
  description = "Enable project monitoring"
  type        = bool
  default     = true
}

# Resource quota configurations
variable "resource_quota" {
  description = "Resource quota settings for the project and its namespaces"
  type = object({
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
  default = null
}

# Container resource limit configurations
variable "container_resource_limit" {
  description = "Resource limits for containers in the project"
  type = object({
    limits_cpu      = string
    limits_memory   = string
    requests_cpu    = string
    requests_memory = string
  })
  default = null
}

variable "querier_host" {
  type = string
}

variable "remote_write_url" {
   type = string
}

locals {
  pid = split(":", rancher2_project.project.id)[1]
  querier_url = "http://${var.querier_host}"
}

resource "rancher2_project" "project" {
  name                      = var.project_name
  cluster_id                = var.cluster_id
  enable_project_monitoring = var.enable_project_monitoring
  #dynamic "project_monitoring_input" {
  #for_each = var.enable_project_monitoring ? [1] : []
  #content {
  #answers = {
  #"alertmanager.enabled"                                = true
  #"federate.enabled"                                    = true
  #"grafana.adminPassword"                               = "admin"
  #"grafana.adminUser"                                   = "admin"
  #"grafana.enabled"                                     = true
  #"grafana.persistence.accessModes[0]"                  = "ReadWriteOnce"
  #"grafana.persistence.enabled"                         = true
  #"grafana.persistence.size"                            = "1Gi"
  #"grafana.persistence.storageClass"                    = "standard"
  #"grafana.sidecar.dashboards.label"                    = "grafana_dashboard"
  #"prometheus.prometheusSpec.evaluationInterval"        = "1m"
  #"prometheus.prometheusSpec.resources.limits.cpu"      = "1000m"
  #"prometheus.prometheusSpec.resources.limits.memory"   = "3000Mi"
  #"prometheus.prometheusSpec.resources.requests.cpu"    = "750m"
  #"prometheus.prometheusSpec.resources.requests.memory" = "750Mi"
  #"prometheus.prometheusSpec.retention"                 = "10d"
  #"prometheus.prometheusSpec.retentionSize"             = "50GB"
  #"prometheus.prometheusSpec.scrapeInterval"            = "30s"
  #}
  #}
  #}
  dynamic "resource_quota" {
    for_each = var.resource_quota != null ? [var.resource_quota] : []
    content {
      project_limit {
        limits_cpu       = resource_quota.value.project_limit.limits_cpu
        limits_memory    = resource_quota.value.project_limit.limits_memory
        requests_storage = resource_quota.value.project_limit.requests_storage
      }
      namespace_default_limit {
        limits_cpu       = resource_quota.value.namespace_default_limit.limits_cpu
        limits_memory    = resource_quota.value.namespace_default_limit.limits_memory
        requests_storage = resource_quota.value.namespace_default_limit.requests_storage
      }
    }
  }
  dynamic "container_resource_limit" {
    for_each = var.container_resource_limit != null ? [var.container_resource_limit] : []
    content {
      limits_cpu      = container_resource_limit.value.limits_cpu
      limits_memory   = container_resource_limit.value.limits_memory
      requests_cpu    = container_resource_limit.value.requests_cpu
      requests_memory = container_resource_limit.value.requests_memory
    }
  }
}

#resource "kubernetes_secret_v1" "thanos-container-config" {
#  count = var.enable_project_monitoring ? 1 : 0
#  metadata {
#    name      = "thanos-container-config"
#    namespace = "cattle-project-${local.pid}-monitoring"
#  }
#  data = {
#    "thanos-config.yaml" = <<EOF
#type: S3
#config:
#  access_key: minioadmin
#  secret_key: minioadmin
#  endpoint: "${var.minio_api_host}"
#  bucket: thanos
#EOF
#  }
#}
# Special nginx proxy configurations
provider "kubernetes" {
  # Your Kubernetes provider configuration here
}

resource "kubernetes_config_map" "nginx_config_tenant" {
  metadata {
    name = "nginx-config-tenant"
    namespace = "cattle-project-${local.pid}-monitoring"
  }

  data = {
    "nginx.conf" = <<EOT
worker_processes      auto;
error_log             /dev/stdout debug;
pid                   /var/cache/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    resolver 8.8.8.8;
    include       /etc/nginx/mime.types;
    log_format    main '[$time_local - $status] $remote_addr - $remote_user $request ($http_referer) $query_path ';
    proxy_connect_timeout       10;
    proxy_read_timeout          180;
    proxy_send_timeout          5;
    proxy_buffering             off;
    proxy_cache_path            /var/cache/nginx/cache levels=1:2 keys_zone=my_zone:100m inactive=1d max_size=10g;

    server {
        listen          8081;
        access_log  /dev/stdout main;

        gzip            on;
        gzip_min_length 1k;
        gzip_comp_level 2;
        gzip_types      text/plain application/javascript application/x-javascript text/css application/xml text/javascript image/jpeg image/gif image/png;
        gzip_vary       on;
        gzip_disable    "MSIE [1-6]\.";

        proxy_set_header Host $host;

        location / {

            proxy_cache         my_zone;
            proxy_cache_valid   200 302 1d;
            proxy_cache_valid   301 30d;
            proxy_cache_valid   any 5m;
            proxy_cache_bypass  $http_cache_control;
            add_header          X-Proxy-Cache $upstream_cache_status;
            add_header          Cache-Control "public";

            proxy_pass     http://localhost:9090/;

            sub_filter_once off;
            sub_filter          'var PATH_PREFIX = "";' 'var PATH_PREFIX = ".";';

            if ($request_filename ~ .*\.(?:js|css|jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm)$) {
                expires             90d;
            }

            rewrite ^/k8s/clusters/.*/proxy(.*) /$1 break;
        }
        location ~ ^/api/v1/query {
            # Rewrite the URI to include the tenant_id
            set $query_path "$args&tenant=${var.owner}"; 

            # Route queries to external Thanos server
            proxy_pass http://${var.querier_host}/api/v1/query?$${query_path};

            proxy_set_header Host ${var.querier_host};
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOT
}
}

# Enable federated project monitoring
resource "kubernetes_manifest" "project_monitoring" {
  depends_on = [ rancher2_project.project ]
  count = var.enable_project_monitoring ? 1 : 0
  manifest = {
    "apiVersion" = "helm.cattle.io/v1alpha1"
    "kind"       = "ProjectHelmChart"
    "metadata" = {
      "name"      = "project-monitoring"
      "namespace" = "cattle-project-${local.pid}"
    }
    "spec" = {
      "helmApiVersion" = "monitoring.cattle.io/v1alpha1"
      "projectNamespaceSelector" = {
        "matchLabels" = {
          "field.cattle.io" = "${local.pid}"
          "objectset.rio.cattle.io/owner-namespace" : "cattle-project-${local.pid}"
        }
      }
      "values" = {
        "alertmanager" = {
          "enabled" = true
        }
        "federate" = {
          "enabled" = true
        }
        "grafana" = {
          "adminPassword" = "prom-operator"
          "adminUser"     = "admin"
          "enabled"       = true
          "sidecar" = {
            "dashboards" = {
              "label" = "grafana_dashboard"
            }
            #"datasources" = {
            #  "url" =  "http://cattle-project-${local.pid}-mon-prometheus.cattle-project-${local.pid}-monitoring:8082/"
            #}
          }
        }
        "prometheus" = {
          "prometheusSpec" = {
            "volumes" = [{
              "name" = "nginx-home"
              "emptyDir" = {}
              },{
              "name" = "prometheus-nginx"
              "configMap" = {
                "name" = "nginx-config-tenant"
                "defaultMode" = 438
              }
            }]
            "externalLabels" = {
               "tenant" = "${var.owner}"
               "tenant_id" = "${var.owner_user_id}"
               "project" = "${var.project_name}"
               "project_id" = "${local.pid}"
            }
            "remoteWrite" = [{ 
              url  = "${var.remote_write_url}/api/v1/receive" 
            }]
            "remoteWriteDashboards" = true
            "evaluationInterval" = "1m"
            "resources" = {
              "limits" = {
                "cpu"    = "1000m"
                "memory" = "3000Mi"
              }
              "requests" = {
                "cpu"    = "750m"
                "memory" = "750Mi"
              }
            }
            "retention"      = "11d"
            "retentionSize"  = "50GB"
            "scrapeInterval" = "30s"
          }
        }
      }
    }
  }
}

resource "rancher2_project_role_template_binding" "project_admin" {
  name             = "project-admin"
  project_id       = rancher2_project.project.id
  role_template_id = "project-owner"
  user_id          = var.owner_user_id
}

output "project_id" {
  value = rancher2_project.project.id
}
output "cluster_id" {
  value = rancher2_project.project.cluster_id
}
