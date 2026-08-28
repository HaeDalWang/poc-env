# ------------------------------------------------------------------------------
# Terraform / Provider 버전 고정
#
# 기반 스택(terraform-eks)과 동일한 버전으로 맞춘다.
# 버전이 어긋나면 같은 클러스터를 두 스택이 서로 다른 방식으로 다루게 되어
# 원인 파악이 어려운 차이가 생긴다.
# ------------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10"

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
