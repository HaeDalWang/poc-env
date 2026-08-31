# 요구되는 테라폼 제공자 목록
terraform {
  required_version = ">= 1.10"

  # Provider 최신화 날짜: 2026년 8월 31일
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
    # 비밀번호를 생성해야 하면 추가
    # random = {
    #   source  = "hashicorp/random"
    #   version = "3.7.2"
    # }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  # false 로 두면 apply 시작 시점에 CRD 를 전부 조회한다.
  # 이 스택이 만드는 CRD 를 같은 apply 에서 쓰면 그때 없어서 실패한다
  lazy_load = true
}
