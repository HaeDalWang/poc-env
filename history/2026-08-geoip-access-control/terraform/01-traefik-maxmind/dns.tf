# DNS is created only after the NLB exists and reports healthy targets, so a
# half-built ingress never answers on a PoC hostname.
data "aws_lb" "traefik" {
  count = var.create_dns_records ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "service.k8s.aws/stack" = "${local.namespace_name}/${local.traefik_release}"
  }

  depends_on = [helm_release.traefik]
}

resource "aws_route53_record" "poc" {
  for_each = var.create_dns_records ? toset(local.all_hosts) : toset([])

  zone_id = var.hosted_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = data.aws_lb.traefik[0].dns_name
    zone_id                = data.aws_lb.traefik[0].zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = endswith(each.value, var.required_poc_dns_suffix)
      error_message = "Refusing to create a DNS record outside required_poc_dns_suffix."
    }
  }
}
