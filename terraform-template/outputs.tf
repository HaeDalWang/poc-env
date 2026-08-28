# ------------------------------------------------------------------------------
# 배선 확인용 출력
# 리소스를 하나도 추가하지 않은 상태에서 apply해도 이 값들이 채워지면
# 기반 스택 조회와 provider 인증이 정상이라는 뜻이다.
# ------------------------------------------------------------------------------
output "stack" {
  description = "이 스택의 이름"
  value       = var.stack
}

output "namespace" {
  description = "이 스택이 사용하는 Kubernetes 네임스페이스"
  value       = local.target_namespace
}

output "cluster_name" {
  description = "연결된 EKS 클러스터 이름"
  value       = local.cluster_name
}

output "cluster_version" {
  description = "연결된 EKS 클러스터 버전"
  value       = local.cluster_version
}

output "vpc_id" {
  description = "기반 스택의 VPC ID"
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "기반 스택의 private 서브넷 ID"
  value       = local.private_subnet_ids
}

output "public_subnet_ids" {
  description = "기반 스택의 public 서브넷 ID"
  value       = local.public_subnet_ids
}

output "database_subnet_ids" {
  description = "기반 스택의 database 서브넷 ID"
  value       = local.database_subnet_ids
}

output "hosted_zone_name" {
  description = "조회된 Route53 hosted zone 이름. route53_zone_name을 비우면 null이다."
  value       = local.hosted_zone_name
}

output "acm_certificate_arn" {
  description = "조회된 ACM 인증서 ARN. acm_certificate_domain을 비우면 null이다."
  value       = local.acm_certificate_arn
}
