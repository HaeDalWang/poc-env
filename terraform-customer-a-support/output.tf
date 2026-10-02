output "alb_dns_name" {
  description = "ALB DNS — Phase 2 에서 NLB 를 거치지 않고 직접 검증할 때 쓴다"
  value       = try(aws_lb.traefik[0].dns_name, null)
}

output "nlb_dns_name" {
  description = "현재 DNS 레코드가 가리키는 로드밸런서"
  value       = local.active_lb.dns_name
}

output "eip_addresses" {
  description = "고정 IP 4개. 전환 전후로 같아야 한다"
  value       = { for az, e in aws_eip.traefik_public : az => e.public_ip }
}

output "certificate_arns" {
  description = "발급된 인증서. NLB 와 ALB 양쪽에 동시에 붙는지 확인용"
  value       = { for d, c in aws_acm_certificate_validation.cert : d => c.certificate_arn }
}

output "waf_web_acl_arn" {
  description = "Count → Block 전환 시 필요"
  value       = try(aws_wafv2_web_acl.traefik[0].arn, null)
}
