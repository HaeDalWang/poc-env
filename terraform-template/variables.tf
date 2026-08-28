# ------------------------------------------------------------------------------
# 기반 스택(terraform-eks) 식별
# ------------------------------------------------------------------------------
variable "region" {
  description = "기반 스택이 배포된 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "기반 스택(terraform-eks)의 project 값. EKS 클러스터 이름과 동일하다."
  type        = string

  validation {
    condition     = length(trimspace(var.project)) > 0
    error_message = "project는 비어 있을 수 없다. terraform-eks/terraform.tfvars의 project와 동일한 값을 넣는다."
  }
}

# ------------------------------------------------------------------------------
# 이 스택 자체의 식별
# ------------------------------------------------------------------------------
variable "stack" {
  description = "이 스택의 이름. 리소스 이름 접두사, 태그, 기본 네임스페이스에 사용한다. (예: sandbox-helm)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.stack))
    error_message = "stack은 소문자, 숫자, 하이픈만 사용하며 영숫자로 시작하고 끝나야 한다. (Kubernetes 네임스페이스 규칙)"
  }
}

variable "tags" {
  description = "이 스택이 생성하는 AWS 리소스에 추가로 부여할 태그"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Kubernetes 배포 대상
# ------------------------------------------------------------------------------
variable "namespace" {
  description = "이 스택이 사용할 Kubernetes 네임스페이스. null이면 stack 값을 그대로 사용한다."
  type        = string
  default     = null

  validation {
    condition     = var.namespace == null ? true : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace는 DNS-1123 label 형식이어야 한다."
  }
}

variable "create_namespace" {
  description = "네임스페이스를 이 스택에서 생성할지 여부. 이미 존재하는 네임스페이스에 배포하면 false로 둔다."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# 선택 조회 대상 (필요 없으면 빈 문자열로 둔다)
# ------------------------------------------------------------------------------
variable "route53_zone_name" {
  description = "Ingress/Gateway 호스트명에 사용할 기존 public Route53 hosted zone 이름. 빈 문자열이면 조회하지 않는다."
  type        = string
  default     = ""
}

variable "acm_certificate_domain" {
  description = "LB 리스너에 사용할 기존 ISSUED ACM 인증서의 primary domain. 빈 문자열이면 조회하지 않는다."
  type        = string
  default     = ""
}
