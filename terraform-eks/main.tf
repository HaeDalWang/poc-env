# 요구되는 테라폼 제공자 목록
terraform {
  # Provider 최신화 날짜: 2026년 8월 15일
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "3.0.0-beta3"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.1"
    }
  }
}

# Kubernetes 제공자 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}
# Kubectl 제공자 설정
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  lazy_load              = true
}
# Helm 제공자 설정
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
