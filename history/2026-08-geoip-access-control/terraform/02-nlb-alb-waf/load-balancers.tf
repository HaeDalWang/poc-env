resource "aws_security_group" "nlb" {
  name_prefix            = "${local.name}-nlb-"
  description            = "PoC frontend NLB security group"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name}-nlb"
  }
}

resource "aws_security_group" "alb" {
  name_prefix            = "${local.name}-alb-"
  description            = "PoC internal ALB security group"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  for_each = var.allowed_ipv4_cidrs

  security_group_id = aws_security_group.nlb.id
  description       = "PoC HTTPS test client"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_alb" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "NLB to internal ALB HTTPS"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_nlb" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTPS from frontend NLB only"
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_traefik" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to Traefik Pod targets"
  referenced_security_group_id = var.traefik_target_security_group_id
  from_port                    = local.traefik_target_port
  to_port                      = local.traefik_target_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "traefik_from_alb" {
  security_group_id            = var.traefik_target_security_group_id
  description                  = "PoC Traefik targets from internal ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = local.traefik_target_port
  to_port                      = local.traefik_target_port
  ip_protocol                  = "tcp"

  lifecycle {
    precondition {
      condition     = var.acknowledge_target_security_group_change
      error_message = "Refusing to change the target security group until acknowledge_target_security_group_change=true is explicitly set."
    }
  }
}

resource "aws_eip" "nlb" {
  for_each = local.public_subnets

  domain = "vpc"

  tags = {
    Name = "${local.name}-nlb-${each.value}"
  }
}

resource "aws_lb" "frontend" {
  name                             = "${local.name}-nlb"
  load_balancer_type               = "network"
  internal                         = false
  ip_address_type                  = "ipv4"
  security_groups                  = [aws_security_group.nlb.id]
  enable_cross_zone_load_balancing = true

  dynamic "subnet_mapping" {
    for_each = local.public_subnets

    content {
      subnet_id     = subnet_mapping.value
      allocation_id = aws_eip.nlb[subnet_mapping.value].id
    }
  }

  tags = {
    Name = "${local.name}-nlb"
  }
}

resource "aws_lb" "inspection" {
  name                       = "${local.name}-alb"
  load_balancer_type         = "application"
  internal                   = true
  ip_address_type            = "ipv4"
  subnets                    = var.private_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "${local.name}-alb"
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "traefik" {
  name             = "${local.name}-traefik"
  port             = local.traefik_target_port
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/health"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name}-traefik"
  }
}

resource "aws_lb_listener" "inspection_https" {
  load_balancer_arn = aws_lb.inspection.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Unknown host"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "protected_hosts" {
  listener_arn = aws_lb_listener.inspection_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }

  condition {
    host_header {
      values = var.protected_hosts
    }
  }
}

resource "aws_lb_listener_rule" "nlb_health" {
  listener_arn = aws_lb_listener.inspection_https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

resource "aws_lb_target_group" "inspection" {
  name        = "${local.name}-alb"
  port        = 443
  protocol    = "TCP"
  target_type = "alb"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = "traffic-port"
    path                = "/health"
    matcher             = "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_lb_target_group_attachment" "inspection" {
  target_group_arn = aws_lb_target_group.inspection.arn
  target_id        = aws_lb.inspection.arn
  port             = 443

  depends_on = [
    aws_lb_listener.inspection_https,
    aws_lb_listener_rule.nlb_health,
  ]
}

resource "aws_lb_listener" "frontend_tcp" {
  load_balancer_arn = aws_lb.frontend.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inspection.arn
  }

  depends_on = [aws_lb_target_group_attachment.inspection]
}
