output "architecture" {
  description = "PoC request path"
  value       = "Client -> NLB(EIP/TCP) -> internal ALB(HTTPS/WAF) -> Traefik(HTTP) -> whoami"
}

output "protected_urls" {
  description = "Exact PoC endpoints protected by host, path, and query scoped WAF rules"
  value       = [for host in var.protected_hosts : "https://${host}/SMS.asmx?WSDL"]
}

output "frontend_nlb_dns_name" {
  description = "Frontend NLB DNS name"
  value       = aws_lb.frontend.dns_name
}

output "frontend_static_ipv4_addresses" {
  description = "Static ingress IPv4 addresses allocated to the PoC NLB"
  value       = [for key in sort(keys(aws_eip.nlb)) : aws_eip.nlb[key].public_ip]
}

output "internal_alb_dns_name" {
  description = "Internal ALB DNS name; direct access must remain blocked"
  value       = aws_lb.inspection.dns_name
}

output "waf_web_acl_arn" {
  description = "Regional WAF Web ACL attached to the internal ALB"
  value       = aws_wafv2_web_acl.this.arn
}

output "waf_mode" {
  description = "Current WAF enforcement mode"
  value       = lower(var.waf_mode)
}

output "waf_log_group_name" {
  description = "Short-retention raw WAF evidence log group"
  value       = aws_cloudwatch_log_group.waf.name
}

output "alb_access_log_bucket" {
  description = "Private short-retention S3 bucket for ALB access evidence"
  value       = aws_s3_bucket.alb_logs.id
}

output "dns_records_enabled" {
  description = "Whether Terraform creates Route53 aliases in this run"
  value       = var.create_dns_records
}
