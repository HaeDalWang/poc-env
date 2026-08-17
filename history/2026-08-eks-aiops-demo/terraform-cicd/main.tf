terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "6.49.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "3.2.0" }
    kubectl    = { source = "alekc/kubectl", version = "2.4.1" }
    helm       = { source = "hashicorp/helm", version = "3.2.0" }
    htpasswd   = { source = "loafoe/htpasswd", version = "1.0.4" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_eks_cluster" "this" { name = var.cluster_name }
data "aws_eks_cluster_auth" "this" { name = var.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  lazy_load              = true
}
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  aws_region = data.aws_region.current.region
}
