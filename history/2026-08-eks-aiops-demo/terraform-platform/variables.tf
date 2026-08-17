variable "cluster_name" {
  description = "대상 EKS 클러스터 이름"
  type        = string
}

variable "acm_certificate_arn" {
  description = "Envoy Gateway NLB에 사용할 ACM 인증서 ARN"
  type        = string
}

variable "envoy_gateway_chart_version" {
  description = "Envoy Gateway Helm 차트 버전"
  type        = string
}
