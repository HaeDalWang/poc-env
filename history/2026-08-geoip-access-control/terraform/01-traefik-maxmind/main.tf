# Option 1 - Traefik middleware + MaxMind GeoIP2 country gate.
#
# Traffic shape reproduced from the customer environment:
#   client -> public NLB (fixed EIP, TLS termination, PROXY protocol v2)
#          -> Traefik `web` entrypoint (plaintext)
#          -> geoip2 middleware (adds X-GeoIP2-* headers)
#          -> checkheaders middleware (403 unless country == KR)
#          -> echo backend
#
# A second entrypoint `pptest` exists for in-cluster PROXY protocol replay so that
# per-country verdicts can be measured without renting an overseas source address.

terraform {
  required_version = ">= 1.14.0, < 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}
