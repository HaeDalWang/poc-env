# region NLB (TCP) — Phase 3
#
# LBC 로는 만들 수 없다. nlb-target-type 어노테이션이 ip/instance 만 받고
# alb 를 지원하지 않는다 (kubernetes-sigs/aws-load-balancer-controller#3553).
# 그래서 Terraform 이 직접 만든다. 이게 "NLB 재생성" 이 필요한 이유다.
#
# EIP 는 생성 시 subnet_mapping 으로만 지정된다. 나중에 못 붙인다.
# 따라서 기존 NLB 삭제 → EIP 분리 → 신규 NLB 생성 순서가 강제되고
# 이 구간이 서비스 단절이다.

# LBC 가 기존 NLB 를 지우고 EIP 가 분리될 때까지 기다린다.
# 이 대기가 없으면 EIP 가 아직 붙어 있는 상태에서 생성이 들어가 실패한다
resource "time_sleep" "nlb_drain" {
  count = var.enable_nlb_tcp ? 1 : 0

  # NLB 삭제 → ENI 해제 → EIP 분리까지 걸리는 시간.
  # 120초로는 모자랐다 (ResourceInUse: The allocation IDs are not available for use)
  create_duration = "240s"

  triggers = {
    service_enabled = var.create_nlb_via_service ? "true" : "false"
  }

  depends_on = [helm_release.traefik]
}

resource "aws_lb" "traefik_public" {
  count = var.enable_nlb_tcp ? 1 : 0

  name                             = "traefik-nlb-${local.env}"
  load_balancer_type               = "network"
  internal                         = false
  enable_cross_zone_load_balancing = true

  dynamic "subnet_mapping" {
    for_each = local.public_azs
    content {
      subnet_id     = local.public_subnets_by_az[subnet_mapping.value]
      allocation_id = aws_eip.traefik_public[subnet_mapping.value].allocation_id
    }
  }

  depends_on = [time_sleep.nlb_drain]
}

# alb 타입 타겟그룹.
# preserve_client_ip 는 이 타입에서 항상 기본값(활성)이고 변경할 수 없다.
# 덕분에 ALB 에 실제 클라이언트 IP 가 도착해 WAF 판정이 정상 동작한다
resource "aws_lb_target_group" "alb" {
  for_each = var.enable_nlb_tcp ? {
    websecure     = 443
    websecure-alt = 8000
    web           = 80
  } : {}

  name        = "traefik-alb-tg-${each.value}"
  target_type = "alb"
  protocol    = "TCP"
  port        = each.value
  vpc_id      = data.aws_vpc.this.id

  # ALB 443 으로 헬스체크가 나간다. SNI 없이 붙으므로 default 인증서가 응답하고,
  # 그 뒤 Traefik 이 라우터 없음으로 404 를 낸다. 경로 전체가 살아있다는 뜻이다
  health_check {
    protocol = "HTTPS"
    path     = "/"
    port     = "443"
    matcher  = "404"
  }
}

resource "aws_lb_target_group_attachment" "alb" {
  for_each = var.enable_nlb_tcp ? aws_lb_target_group.alb : {}

  target_group_arn = each.value.arn
  target_id        = aws_lb.traefik[0].arn
  port             = each.value.port
}

# TLS 가 아니라 TCP 여야 한다.
# NLB 의 TLS 리스너는 alb 타입 타겟그룹으로 포워딩할 수 없다.
# 근거: ELB 문서 application-load-balancer-target
resource "aws_lb_listener" "nlb" {
  for_each = var.enable_nlb_tcp ? aws_lb_target_group.alb : {}

  load_balancer_arn = aws_lb.traefik_public[0].arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = each.value.arn
  }

  depends_on = [aws_lb_target_group_attachment.alb]
}

# endregion

# region DNS
#
# external-dns 가 아니라 Terraform 이 직접 만든다.
# 전환 중에 레코드가 자동으로 바뀌면 단절 구간 측정(V8)이 오염된다.
#
# Phase 1·2 는 LBC 가 만든 NLB, Phase 3 부터는 Terraform 이 만든 NLB 를 가리킨다.
# 두 변수를 동시에 false/true 로 바꿔 한 번의 apply 로 전환한다.
# 둘 다 false 인 상태는 가리킬 LB 가 없어 apply 가 실패한다

locals {
  active_lb = var.enable_nlb_tcp ? {
    dns_name = try(aws_lb.traefik_public[0].dns_name, "")
    zone_id  = try(aws_lb.traefik_public[0].zone_id, "")
    } : {
    dns_name = try(data.aws_lb.traefik_service[0].dns_name, "")
    zone_id  = try(data.aws_lb.traefik_service[0].zone_id, "")
  }
}

# LBC 가 Traefik Service 로 만든 NLB
data "aws_lb" "traefik_service" {
  count = var.create_nlb_via_service ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "service.k8s.aws/stack" = "traefik/traefik"
  }

  depends_on = [helm_release.traefik]
}

resource "aws_route53_record" "service" {
  for_each = toset(local.all_subdomains)

  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = local.active_lb.dns_name
    zone_id                = local.active_lb.zone_id
    evaluate_target_health = true
  }
}

# endregion
