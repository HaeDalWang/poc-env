# region ALB 보안그룹
#
# NLB 의 alb 타입 타겟그룹은 클라이언트 IP 보존이 기본이고 끌 수 없다.
# 그래서 ALB 에 도착하는 출발지는 NLB 가 아니라 실제 클라이언트 IP 다.
# NLB 대역만 열면 전부 막힌다 — 0.0.0.0/0 이어야 한다.
# 근거: ELB 문서 load-balancer-target-groups (preserve_client_ip)

resource "aws_security_group" "alb" {
  count = var.enable_alb ? 1 : 0

  name        = "traefik-alb-${local.env}"
  description = "NLB to ALB(WAF) to Traefik"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "traefik-alb-${local.env}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = var.enable_alb ? toset(["80", "443", "8000"]) : toset([])

  security_group_id = aws_security_group.alb[0].id
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "client ip is preserved through NLB alb-type target group"
}

resource "aws_vpc_security_group_egress_rule" "alb" {
  count = var.enable_alb ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# endregion

# region ALB
#
# TLS 종료와 WAF 만 담당한다. Host 기반 라우팅은 그대로 Traefik 이 한다.
# ALB 에서 라우팅까지 하면 Traefik 과 역할이 겹치고 설정 위치가 둘로 갈린다.

resource "aws_lb" "traefik" {
  count = var.enable_alb ? 1 : 0

  name               = "traefik-alb-${local.env}"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb[0].id]

  subnets = [
    for az in local.public_azs : local.public_subnets_by_az[az]
  ]
}

# 443 — 기존 NLB 443 리스너를 대체한다. 인증서 4개 전부
resource "aws_lb_listener" "websecure" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.traefik[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # 리스너마다 default 인증서 1개는 LB 당 25개 한도에서 제외된다
  certificate_arn = aws_acm_certificate_validation.cert[local.all_subdomains[0]].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websecure[0].arn
  }
}

resource "aws_lb_listener_certificate" "websecure" {
  for_each = var.enable_alb ? toset(slice(local.all_subdomains, 1, length(local.all_subdomains))) : toset([])

  listener_arn    = aws_lb_listener.websecure[0].arn
  certificate_arn = aws_acm_certificate_validation.cert[each.key].certificate_arn
}

# 8000 — 고객 질문 ②의 답이 되는 부분.
# NLB 어노테이션 방식과 달리 리스너마다 필요한 인증서만 올린다.
# 여기 목록을 늘리면 ALB 전체 합계가 늘어난다 (LB 당 25개, default 제외)
resource "aws_lb_listener" "websecure_alt" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.traefik[0].arn
  port              = 8000
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cert[local.alt_port_subdomains[0]].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websecure_alt[0].arn
  }
}

resource "aws_lb_listener" "web" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.traefik[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}

# endregion

# region ALB 타겟그룹
#
# ALB 가 TLS 를 끝내고 평문 HTTP 로 Traefik 에 넘긴다.
# Traefik values 의 ports.*.http.tls.enabled = false 와 짝이다.
#
# 컨테이너 포트 — web 8000 / websecure 8443 / websecure-alt 8444

resource "aws_lb_target_group" "websecure" {
  count = var.enable_alb ? 1 : 0

  name        = "traefik-ws-${local.env}"
  port        = 8443
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.this.id
  target_type = "ip"

  # /ping 은 traefik entrypoint(9000) 에만 붙어 있어 여기로는 응답하지 않는다.
  # 매칭되는 라우터가 없을 때 Traefik 이 내는 404 를 살아있음의 근거로 쓴다.
  # 200 만 기대하면 타겟이 전부 unhealthy 가 되고 트래픽이 끊긴다
  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "404"
  }
}

resource "aws_lb_target_group" "websecure_alt" {
  count = var.enable_alb ? 1 : 0

  name        = "traefik-wsalt-${local.env}"
  port        = 8444
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.this.id
  target_type = "ip"

  # /ping 은 traefik entrypoint(9000) 에만 붙어 있어 여기로는 응답하지 않는다.
  # 매칭되는 라우터가 없을 때 Traefik 이 내는 404 를 살아있음의 근거로 쓴다.
  # 200 만 기대하면 타겟이 전부 unhealthy 가 되고 트래픽이 끊긴다
  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "404"
  }
}

resource "aws_lb_target_group" "web" {
  count = var.enable_alb ? 1 : 0

  name        = "traefik-web-${local.env}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.this.id
  target_type = "ip"

  # /ping 은 traefik entrypoint(9000) 에만 붙어 있어 여기로는 응답하지 않는다.
  # 매칭되는 라우터가 없을 때 Traefik 이 내는 404 를 살아있음의 근거로 쓴다.
  # 200 만 기대하면 타겟이 전부 unhealthy 가 되고 트래픽이 끊긴다
  health_check {
    protocol = "HTTP"
    path     = "/"
    matcher  = "404"
  }
}

# endregion

# region TargetGroupBinding
#
# ALB 가 Traefik Pod 로 트래픽을 보내는 방법이 이것이다.
# LBC 가 LB 를 만드는 게 아니라, Terraform 이 만든 타겟그룹에 Pod IP 를 등록만 한다.
# customer-a 레포의 주석 처리된 traefik_public_websecure_8000_tgb 와 같은 패턴이다.
#
# networking.ingress 를 넣으면 LBC 가 노드 보안그룹에 규칙을 자동으로 넣는다.
# 빼면 헬스체크가 조용히 실패한다.

resource "kubernetes_service_v1" "traefik_tgb" {
  count = var.enable_alb ? 1 : 0

  metadata {
    name      = "traefik-tgb"
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "traefik"
      "app.kubernetes.io/instance" = "traefik-traefik"
    }

    port {
      name        = "websecure"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }

    port {
      name        = "websecure-alt"
      port        = 8444
      target_port = 8444
      protocol    = "TCP"
    }

    port {
      name        = "web"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }
  }
}

resource "kubectl_manifest" "traefik_tgb" {
  for_each = var.enable_alb ? {
    websecure     = { port = 8443, arn = aws_lb_target_group.websecure[0].arn }
    websecure-alt = { port = 8444, arn = aws_lb_target_group.websecure_alt[0].arn }
    web           = { port = 8000, arn = aws_lb_target_group.web[0].arn }
  } : {}

  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "traefik-${each.key}"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      serviceRef = {
        name = kubernetes_service_v1.traefik_tgb[0].metadata[0].name
        port = each.value.port
      }
      targetGroupARN = each.value.arn
      targetType     = "ip"
      networking = {
        ingress = [
          {
            from  = [{ securityGroup = { groupID = aws_security_group.alb[0].id } }]
            ports = [{ protocol = "TCP", port = each.value.port }]
          }
        ]
      }
    }
  })

  lifecycle {
    # spec.targetGroupARN 은 immutable — TG 가 replace 되면 patch 가 아니라 delete → create 여야 한다
    replace_triggered_by = [aws_lb_target_group.websecure]
  }
}

# endregion

# region WAF
#
# 규칙 하나에 도메인 목록과 국가 조건을 함께 넣는다.
# 도메인 추가는 local.waf_blocked_hosts 에 한 줄이다.
#
# 처음에는 반드시 Count 로 켠다. HostingProviderIPList 는 클라우드에서 오는
# 트래픽을 막는데, 문자서비스는 고객사 서버가 호출하는 B2B API 라 전제가 반대다.
# 연동 고객사 서버가 클라우드에 있으면 정상 요청이 막힌다.

locals {
  # 국외 차단 대상. etc 는 일부러 뺐다 — 같은 LB 를 쓰지만 차단 대상이 아닌 도메인 역할
  waf_blocked_hosts = [
    for d in ["sms", "testsms", "manager"] : "${d}.${var.domain_name}"
  ]
}

resource "aws_wafv2_web_acl" "traefik" {
  count = var.enable_alb ? 1 : 0

  name  = "traefik-${local.env}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # 대상 도메인 && 국가가 KR 이 아님 → 차단
  rule {
    name     = "sms-geo-block"
    priority = 1

    # Count 로 관찰 후 block 으로 바꾼다. 바꾸는 즉시 403 이 나간다.
    # waf_block_test 는 검증용 토글이다 (variables.tf 참고)
    action {
      dynamic "count" {
        for_each = var.waf_block_test ? [] : [1]
        content {}
      }
      dynamic "block" {
        for_each = var.waf_block_test ? [1] : []
        content {}
      }
    }

    statement {
      and_statement {
        statement {
          or_statement {
            dynamic "statement" {
              for_each = local.waf_blocked_hosts
              content {
                byte_match_statement {
                  positional_constraint = "EXACTLY"
                  search_string         = statement.value

                  field_to_match {
                    single_header {
                      name = "host"
                    }
                  }

                  text_transformation {
                    priority = 0
                    type     = "LOWERCASE"
                  }
                }
              }
            }
          }
        }

        statement {
          not_statement {
            statement {
              geo_match_statement {
                country_codes = var.waf_block_test ? ["US"] : ["KR"]
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "sms-geo-block"
      sampled_requests_enabled   = true
    }
  }

  # VPN·프록시·Tor. 방안 1 에서 상용 DB 를 사야 했던 부분을 AWS 가 대신한다
  rule {
    name     = "anonymous-ip"
    priority = 2

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAnonymousIpList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "anonymous-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "traefik-${local.env}"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "traefik" {
  count = var.enable_alb ? 1 : 0

  resource_arn = aws_lb.traefik[0].arn
  web_acl_arn  = aws_wafv2_web_acl.traefik[0].arn
}

# endregion
