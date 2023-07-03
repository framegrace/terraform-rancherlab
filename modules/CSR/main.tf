#CSR
variable "dns-name" {
  type = string
}
variable "subject" {
  type = object({
    country             = string
    province            = string
    locality            = string
    common_name         = string
    organization        = string
    organizational_unit = string
  })
  default = {
    country             = "ES-CT"
    province            = "Barcelona"
    locality            = "Manresa"
    common_name         = ""
    organization        = "Marc Gracia"
    organizational_unit = "Devops"
  }
}
variable "ca_cert" {
  type = string
}
variable "ca_key" {
  type = string
}

locals {
  subject = {
    country             = var.subject.country
    province            = var.subject.province
    locality            = var.subject.locality
    common_name         = var.subject.common_name != "" ? var.subject.common_name : var.dns-name
    organization        = var.subject.organization
    organizational_unit = var.subject.organizational_unit
  }
}
# Create private key for server certificate 
resource "tls_private_key" "cert_key" {
  algorithm = "RSA"
}

resource "local_file" "cert_key_file" {
  content  = tls_private_key.cert_key.private_key_pem
  filename = "${path.module}/certs/dev.cloudmanthan.key"
}

# Create CSR for for server certificate 
resource "tls_cert_request" "cert_csr" {

  private_key_pem = tls_private_key.cert_key.private_key_pem

  dns_names = [var.dns-name]

  subject {
    country             = local.subject.country
    province            = local.subject.province
    locality            = local.subject.locality
    common_name         = local.subject.common_name
    organization        = local.subject.organization
    organizational_unit = local.subject.organizational_unit
  }
}

# Sign Seerver Certificate by Private CA 
resource "tls_locally_signed_cert" "cert" {
  // CSR by the development servers
  cert_request_pem = tls_cert_request.cert_csr.cert_request_pem
  // CA Private key 
  ca_private_key_pem = var.ca_key
  // CA certificate
  ca_cert_pem = var.ca_cert

  validity_period_hours = 43800

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth",
  ]
}

resource "local_file" "cert_cert" {
  content  = tls_locally_signed_cert.cert.cert_pem
  filename = "${path.module}/certs/dev.cloudmanthan.cert"
}

output "cert_pem" {
  value = tls_locally_signed_cert.cert.cert_pem
}

output "cert_key" {
  value = tls_private_key.cert_key.private_key_pem
}
