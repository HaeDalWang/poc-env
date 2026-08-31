variable "project" {
  description = "terraform-eks의 project. EKS 클러스터 이름과 같다."
  type        = string
}

variable "acm_certificate_domain" {
  description = "NLB가 TLS를 종단할 ACM 인증서의 도메인"
  type        = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "envoy_gateway_chart_version" {
  type        = string
  description = "envoy_gateway_chart의 버전"
}