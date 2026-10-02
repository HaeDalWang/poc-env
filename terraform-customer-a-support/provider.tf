# 요구되는 테라폼 제공자 목록
#
# 주의 — 고객(customer-a) 레포와 provider 버전이 다르다
#   customer-a prod : kubernetes 2.38.0 / helm 2.16.0 / kubectl 2.1.3
#   여기      : kubernetes 3.2.1  / helm 3.2.0  / kubectl 3.0.0-beta3
# helm 3.x 는 provider 블록 문법이 `kubernetes = { }` 로 바뀌었다.
# 리소스 코드는 양쪽이 동일하므로 고객에게는 리소스 파일만 전달한다.
terraform {
  required_version = ">= 1.10"

  # Provider 최신화 날짜: 2026년 9월 8일
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.60.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "3.0.0-beta3"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.1"
    }
  }
}

# AWS 제공자 설정
provider "aws" {
  region = var.region

  # 이 스택이 만든 리소스만 골라내려면 태그가 유일한 수단이다.
  # envoy-gateway 등 다른 스택 리소스와 섞이지 않게 한다.
  default_tags {
    tags = local.tags
  }
}

# Kubernetes 제공자 설정
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Helm 제공자 설정
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Kubectl 제공자 설정 — TargetGroupBinding 매니페스트 적용용
provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  lazy_load              = true
}
