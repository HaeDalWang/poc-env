# =============================================================================
# CloudFront + AWS WAF (미적용)
#
# AWS WAF 는 NLB 에 붙지 않는다. 지원 대상은 CloudFront / ALB / API Gateway 등이다.
# "AWS WAF" 를 명시적으로 요구받으면 앞단에 CloudFront 를 두고 거기에 WAF 를 붙인다.
# https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html
#
# 전환할 때 gateway.tf 에서 바뀌는 건 세 줄이다.
#   EnvoyProxy  source-ranges 대신 prefix-lists: pl-22a6434b
#               = com.amazonaws.global.cloudfront.origin-facing.
#                 NLB 를 CloudFront 에서만 받게 잠가 우회를 막는다. 대역 갱신은 AWS 가 한다.
#   Gateway     external-dns.alpha.kubernetes.io/target: <배포 도메인>
#               Gateway 에 달면 붙어 있는 모든 HTTPRoute 의 DNS 가 CloudFront 로 나간다.
#               앱을 추가할 때마다 손댈 필요가 없다.
#   ClientTrafficPolicy  numTrustedHops: 1 -> 2. 홉이 하나 늘어난다.
#                        안 바꾸면 클라이언트 IP 자리에 CloudFront IP 가 잡혀
#                        IP 기반 WAF 룰이 전부 헛돈다.
#
# 알아둘 것
#   - 인증서와 WAF 는 us-east-1 에만 만들 수 있다. 지금 인증서는 ap-northeast-2 라 별도 발급.
#   - aliases 는 와일드카드로 잡는다. 아니면 앱이 늘 때마다 배포를 고쳐야 한다.
#   - git push 같은 대용량 요청은 CloudFront 응답 타임아웃(기본 30초, 최대 180초)에 걸릴 수 있다.
# =============================================================================

# provider "aws" {
#   alias  = "us_east_1"
#   region = "us-east-1"
# }

# data "aws_acm_certificate" "cloudfront" {
#   provider    = aws.us_east_1
#   domain      = var.acm_certificate_domain
#   statuses    = ["ISSUED"]
#   most_recent = true
# }

# resource "aws_wafv2_web_acl" "this" {
#   provider = aws.us_east_1
#   name     = "${var.project}-waf"
#   scope    = "CLOUDFRONT"
#
#   default_action {
#     allow {}
#   }
#
#   # 관리형 룰 그룹. 처음에는 count 로 두고 오탐을 본 뒤 block 으로 바꾼다.
#   # https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html
#   rule {
#     name     = "common"
#     priority = 1
#     override_action {
#       none {}
#     }
#     statement {
#       managed_rule_group_statement {
#         vendor_name = "AWS"
#         name        = "AWSManagedRulesCommonRuleSet"
#       }
#     }
#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "common"
#       sampled_requests_enabled   = true
#     }
#   }
#
#   visibility_config {
#     cloudwatch_metrics_enabled = true
#     metric_name                = "${var.project}-waf"
#     sampled_requests_enabled   = true
#   }
# }

# resource "aws_cloudfront_distribution" "this" {
#   enabled    = true
#   aliases    = ["*.${var.acm_certificate_domain}"]
#   web_acl_id = aws_wafv2_web_acl.this.arn
#
#   origin {
#     domain_name = "<NLB DNS 이름>"
#     origin_id   = "nlb"
#     custom_origin_config {
#       origin_protocol_policy = "https-only"
#       http_port              = 80
#       https_port             = 443
#       origin_ssl_protocols   = ["TLSv1.2"]
#     }
#   }
#
#   default_cache_behavior {
#     target_origin_id       = "nlb"
#     viewer_protocol_policy = "redirect-to-https"
#     allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
#     cached_methods         = ["GET", "HEAD"]
#
#     # 동적 트래픽이라 캐시를 끄고 뷰어 요청을 그대로 넘긴다.
#     # Managed-CachingDisabled / Managed-AllViewer
#     cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
#     origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
#   }
#
#   restrictions {
#     geo_restriction {
#       restriction_type = "none"
#     }
#   }
#
#   viewer_certificate {
#     acm_certificate_arn      = data.aws_acm_certificate.cloudfront.arn
#     ssl_support_method       = "sni-only"
#     minimum_protocol_version = "TLSv1.2_2021"
#   }
# }
