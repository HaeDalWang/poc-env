variable "project" {
  description = "terraform-eks의 project. EKS 클러스터 이름과 같다."
  type        = string
}

variable "domain_name" {
  description = "기준 도메인. GitLab은 gitlab.<domain_name>으로 노출된다."
  type        = string
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "gitlab_chart_version" {
  type        = string
  description = "GitLab 공식 차트 버전"
}

variable "cloudnative_pg_chart_version" {
  type        = string
  description = "CloudNativePG operator 차트 버전"
}

variable "valkey_chart_version" {
  type        = string
  description = "Valkey 공식 차트 버전"
}
