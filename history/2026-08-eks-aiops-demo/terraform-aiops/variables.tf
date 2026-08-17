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

variable "kagent_crds_chart_version" { type = string }
variable "kagent_chart_version" { type = string }
variable "kagent_aws_mcp_proxy_version" { type = string }
variable "kagent_bedrock_model_id" { type = string }

variable "kagent_slack_bot_token" {
  type      = string
  sensitive = true
}

variable "kagent_slack_channel_id" { type = string }

variable "kagent_grafana_service_account" {
  type      = string
  sensitive = true
}
