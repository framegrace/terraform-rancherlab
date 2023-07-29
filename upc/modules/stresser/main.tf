variable "replica_count" {
  description = "Number of replicas"
  default     = 3
}

variable "cpu_request" {
  description = "CPU request"
  default     = "200m"
}

variable "cpu_limit" {
  description = "CPU limit"
  default     = "500m"
}

variable "memory_request" {
  description = "Memory request"
  default     = "128Mi"
}

variable "memory_limit" {
  description = "Memory limit"
  default     = "256Mi"
}

variable "stress_cpu" {
  description = "Number of workers spinning on sqrt()"
  default     = "2"
}

variable "stress_io" {
  description = "Number of workers spinning on sync()"
  default     = "1"
}

variable "stress_vm" {
  description = "Number of workers spinning on malloc()/free()"
  default     = "2"
}

variable "stress_vm_bytes" {
  description = "Bytes allocated per vm worker"
  default     = "128M"
}

resource "kubernetes_deployment" "stress" {
  metadata {
    name = "stress-deployment"
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        app = "stress"
      }
    }

    template {
      metadata {
        labels = {
          app = "stress"
        }
      }

      spec {
        container {
          image = "progrium/stress"
          name  = "stress"

          resources {
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }

            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
          }

          args = [
            "--cpu", var.stress_cpu,
            "--io", var.stress_io,
            "--vm", var.stress_vm,
            "--vm-bytes", var.stress_vm_bytes,
          ]
        }
      }
    }
  }
}
