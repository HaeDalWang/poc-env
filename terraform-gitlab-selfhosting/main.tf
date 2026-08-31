# 기본 서울 리전 terraform-eks와 동일하게 할 것
data "aws_eks_cluster" "this" { name = var.project }

data "aws_eks_cluster_auth" "this" { name = var.project }

# IRSA 신뢰 정책에 쓸 계정 ID
data "aws_caller_identity" "this" {}

locals {
  # IRSA용 OIDC provider ARN. terraform-eks의 EKS 모듈이 만든 것을 조회로 조립한다
  oidc_issuer_host  = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:oidc-provider/${local.oidc_issuer_host}"

  gitlab_host = "gitlab.${var.domain_name}"
}
