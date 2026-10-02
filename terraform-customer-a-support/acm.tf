# region ACM
#
# customer-a prod 의 aws_acm_certificate "cert" 패턴을 그대로 따른다.
# 서브도메인마다 개별 인증서를 발급하고 DNS 검증을 Route53 에 자동 등록한다.
#
# 검증 포인트 — 여기서 만든 인증서 ARN 을
#   Phase 1 : Traefik Service 어노테이션(NLB)
#   Phase 2 : ALB 리스너
# 양쪽에 동시에 붙인다. 삭제·재발급 없이 재사용되는지가 고객 질문 ①이다.

resource "aws_acm_certificate" "cert" {
  for_each = toset(local.all_subdomains)

  domain_name       = "${each.key}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for pair in flatten([
      for domain, cert in aws_acm_certificate.cert : [
        for dvo in cert.domain_validation_options : {
          key    = domain
          name   = dvo.resource_record_name
          type   = dvo.resource_record_type
          record = dvo.resource_record_value
        }
      ]
    ]) : pair.key => pair
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cert" {
  for_each = aws_acm_certificate.cert

  certificate_arn         = each.value.arn
  validation_record_fqdns = [aws_route53_record.cert_validation[each.key].fqdn]
}

# endregion
