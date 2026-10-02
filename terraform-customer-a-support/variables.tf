variable "region" {
  description = "리소스를 생성할 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "대상 EKS 클러스터 이름 (이 스택은 클러스터를 만들지 않고 조회만 한다)"
  type        = string
  default     = "eks-poc"
}

variable "domain_name" {
  description = "Route53 퍼블릭 호스팅 존 이름"
  type        = string
  default     = "seungdobae.com"
}

variable "traefik_chart_version" {
  description = "Traefik chart 버전 (customer-a prod 와 동일해야 재현 의미가 있다)"
  type        = string

  validation {
    condition     = can(regex("^39\\.", var.traefik_chart_version))
    error_message = "customer-a prod 는 chart 39.x 를 쓴다. 다른 버전이면 재현이 아니다. (현재: ${var.traefik_chart_version})"
  }
}

# region PoC 단계 토글
#
# Phase 1 → 2 → 3 을 순서대로 재현하기 위한 스위치다.
# 고객 레포로 이식할 때는 전부 제거하고 최종 상태만 남긴다.

variable "enable_alb" {
  description = "Phase 2 — ALB + WAF 생성. false 면 Phase 1 상태(NLB → Traefik)로만 둔다"
  type        = bool
  default     = false
}

variable "create_nlb_via_service" {
  description = "Phase 3 — true 면 Traefik Service 가 NLB 를 만든다(현행). false 로 바꾸면 NLB 가 삭제되고 EIP 가 분리된다"
  type        = bool
  default     = true
}

variable "waf_block_test" {
  description = "검증용 — 국가 조건을 KR 에서 US 로 반전하고 action 을 block 으로 바꾼다. 국내에서 국외 차단 동작을 재현할 때만 켠다"
  type        = bool
  default     = false
}

variable "enable_nlb_tcp" {
  description = "Phase 3 — Terraform 이 직접 TCP NLB 를 만들어 EIP 를 재점유하고 ALB 로 포워딩한다"
  type        = bool
  default     = false
}

# endregion
