variable "cluster_name" { type = string }
variable "hosted_zone_name" { type = string }

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
  description = "AIOps 계층의 notification relay URL"
  default     = "http://kagent-alert-relay.kagent:8080/"
}

variable "argocd_chart_version" { type = string }
