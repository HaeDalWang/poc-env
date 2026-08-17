# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}
locals {
  azs = slice(data.aws_availability_zones.azs.names, 0, min(4, length(data.aws_availability_zones.azs.names)))
}
# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
# 기존 Route53 public hosted zone
data "aws_route53_zone" "this" {
  name         = var.route53_zone_name
  private_zone = false
}

# 기존 ACM 인증서
data "aws_acm_certificate" "this" {
  domain      = var.acm_certificate_domain
  statuses    = ["ISSUED"]
  most_recent = true
}
