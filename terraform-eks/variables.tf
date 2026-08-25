variable "project" {
  description = "프로젝트 및 EKS 클러스터 이름"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
}

variable "aws_load_balancer_controller_chart_version" {
  description = "AWS Load Balancer Controller Helm 차트 버전"
  type        = string
}

variable "route53_zone_name" {
  description = "ExternalDNS가 관리할 기존 public Route53 hosted zone 이름"
  type        = string
}

variable "acm_certificate_domain" {
  description = "조회할 기존 ISSUED ACM 인증서의 primary domain"
  type        = string
}

variable "gateway_api_crd_version" {
  description = "GatewayAPI CRD의 버전"
  type        = string
}