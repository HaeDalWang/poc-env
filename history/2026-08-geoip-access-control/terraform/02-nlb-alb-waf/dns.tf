resource "aws_route53_record" "protected" {
  for_each = var.create_dns_records ? toset(var.protected_hosts) : toset([])

  zone_id = var.hosted_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.frontend.dns_name
    zone_id                = aws_lb.frontend.zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = endswith(each.value, var.required_poc_dns_suffix)
      error_message = "Refusing to create a DNS record outside required_poc_dns_suffix."
    }
  }

  depends_on = [
    aws_lb_listener.frontend_tcp,
    aws_wafv2_web_acl_association.inspection,
    kubernetes_manifest.traefik_target_group_binding,
  ]
}
