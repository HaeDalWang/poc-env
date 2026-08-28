# ------------------------------------------------------------------------------
# AWS 제공자
# 이 스택이 만드는 AWS 리소스에만 default_tags가 붙는다.
# 기반 스택이 만든 리소스에는 영향이 없다.
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# ------------------------------------------------------------------------------
# 기반 스택이 만든 EKS 클러스터에 연결
#
# 인증 토큰은 data.aws_eks_cluster_auth 기준 15분 만료다.
# apply가 그보다 길어질 가능성이 있으면 아래 exec 블록으로 바꾼다.
#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
#   }
# ------------------------------------------------------------------------------
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
  lazy_load              = true
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
