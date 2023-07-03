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
    common_name         = "UPC K8s Lab CA"
    organization        = "Marc Gracia"
    organizational_unit = "Devops"
  }
}
resource "tls_private_key" "ca_private_key" {
  algorithm = "RSA"
}
#
resource "local_file" "_ca_key" {
  content  = tls_private_key.ca_private_key.private_key_pem
  filename = "${path.module}/certs/CA.key"
}

resource "tls_self_signed_cert" "ca_cert" {
  private_key_pem = tls_private_key.ca_private_key.private_key_pem

  is_ca_certificate = true

  subject {
    country             = var.subject.country
    province            = var.subject.province
    locality            = var.subject.locality
    common_name         = var.subject.common_name
    organization        = var.subject.organization
    organizational_unit = var.subject.organizational_unit
  }

  validity_period_hours = 43800 //  1825 days or 5 years

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "local_file" "ca_cert_file" {
  content  = tls_self_signed_cert.ca_cert.cert_pem
  filename = "${path.module}/certs/CA.cert"
}

output "ca-cert-pem" {
  value = tls_self_signed_cert.ca_cert.cert_pem
}

output "ca-priv-key-pem" {
  value = tls_private_key.ca_private_key.private_key_pem
}
