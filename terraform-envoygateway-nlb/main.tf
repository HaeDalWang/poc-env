# 기본 서울 리전 terraform-eks와 동일하게 할 것
data "aws_eks_cluster" "this" { name = var.project }

data "aws_eks_cluster_auth" "this" { name = var.project }

# terraform-eks의 인증서
data "aws_acm_certificate" "this" {
  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}