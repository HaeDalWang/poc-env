# 기본 서울 리전 terraform-eks와 동일하게 할 것
data "aws_eks_cluster" "this" { name = var.project }

data "aws_eks_cluster_auth" "this" { name = var.project }

# terraform-eks 의 값이 더 필요하면 여기에 조회를 추가한다.
# terraform_remote_state 를 쓰지 않는 이유는 CLAUDE.md 참조
#
# ACM 인증서
# data "aws_acm_certificate" "this" {
#   domain      = var.acm_certificate_domain
#   statuses    = ["ISSUED"]
#   most_recent = true
# }
#
# IRSA 를 쓸 때 필요한 계정 ID 와 OIDC provider
# data "aws_caller_identity" "this" {}
# locals {
#   oidc_issuer_host  = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
#   oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:oidc-provider/${local.oidc_issuer_host}"
# }
