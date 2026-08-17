variable "cluster_name" {
  type = string
}

variable "hosted_zone_name" {
  type = string
}

variable "gateway_name" {
  type    = string
  default = "eg"
}

variable "gateway_namespace" {
  type    = string
  default = "envoy-gateway-system"
}

variable "gateway_listener" {
  type    = string
  default = "https"
}

variable "kagent_relay_url" {
  type        = string
  description = "AIOps 계층의 alert relay URL. AIOps 미설치 시 알림만 전달되지 않으며 관측성 설치는 독립적으로 완료됨"
  default     = "http://kagent-alert-relay.kagent:8080/"
}

variable "prometheus_operator_crds_chart_version" { type = string }
variable "kube_prometheus_stack_chart_version" { type = string }
variable "thanos_chart_version" { type = string }
variable "loki_chart_version" { type = string }
variable "k8s_monitoring_chart_version" { type = string }
variable "tempo_distributed_chart_version" { type = string }
