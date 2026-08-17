output "gateway_name" {
  description = "공유 Gateway 이름"
  value       = local.envoy_gateway_name
}

output "gateway_namespace" {
  description = "공유 Gateway 네임스페이스"
  value       = local.envoy_gateway_namespace
}

output "gateway_listener" {
  description = "공유 HTTPS listener 이름"
  value       = local.envoy_gateway_listener
}
