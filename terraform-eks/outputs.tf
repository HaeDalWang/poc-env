output "cluster_name" {
  description = "계층별 Terraform에서 사용할 EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "hosted_zone_name" {
  description = "ExternalDNS와 서비스 계층에서 사용할 기존 Route53 hosted zone 이름"
  value       = trimsuffix(data.aws_route53_zone.this.name, ".")
}

output "hosted_zone_id" {
  description = "ExternalDNS가 관리할 기존 Route53 hosted zone ID"
  value       = data.aws_route53_zone.this.zone_id
}

output "acm_certificate_arn" {
  description = "플랫폼 계층의 Envoy Gateway에서 사용할 기존 ACM 인증서 ARN"
  value       = data.aws_acm_certificate.this.arn
}
