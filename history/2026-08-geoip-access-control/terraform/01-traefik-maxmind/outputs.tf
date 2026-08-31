output "option" {
  description = "PoC option implemented by this Terraform root"
  value       = "1: NLB (PROXY v2) -> Traefik -> MaxMind GeoIP2 -> country header gate"
}

output "nlb_eip_addresses" {
  description = "Fixed ingress IPv4 addresses to target with curl --resolve"
  value       = { for subnet_id, eip in aws_eip.nlb : subnet_id => eip.public_ip }
}

output "namespace" {
  description = "Kubernetes namespace holding every option 1 resource"
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "protected_hosts" {
  description = "Hosts whose in-scope requests pass through the country gate"
  value       = var.protected_hosts
}

output "control_host" {
  description = "Unprotected host used as the negative control"
  value       = var.control_host
}

output "active_scope_rule" {
  description = "Traefik rule currently guarding the protected route"
  value       = local.protected_rule
}

output "test_targets" {
  description = "Request targets used by the verification matrix"
  value = {
    protected = var.protected_scope == "wsdl_only" ? "/SMS.asmx?WSDL" : "/SMS.asmx"
    observe   = "/observe"
    baseline  = "/not-protected"
    control   = "/"
  }
}

output "pptest_endpoint" {
  description = "In-cluster PROXY v2 replay endpoint. Never exposed through the NLB."
  value       = "${kubernetes_service_v1.traefik_pptest.metadata[0].name}.${local.namespace_name}.svc.cluster.local:9000"
}

output "database_state" {
  description = "How the country database is supplied for this deployment"
  value = var.simulate_missing_db ? "absent on purpose - every request is stamped XX and rejected by the gate" : (
    var.db_refresh_interval_hours > 0 ?
    "downloaded at Pod start, then rewritten every ${var.db_refresh_interval_hours}h by a sidecar the plugin never rereads" :
    "downloaded once at Pod start by geoipupdate; a Pod restart is the only way to pick up a newer database"
  )
}

output "capability_boundary" {
  description = "What this plugin chain can and cannot demonstrate"
  value       = "Country allow/deny only. traefikgeoip2 reads a GeoLite2 country database and has no access to MaxMind Anonymous IP data, so VPN and proxy detection is out of scope for option 1."
}

output "traefik_values_yaml" {
  description = "Rendered Helm values, so the release can be checked with helm template before apply"
  value       = local.traefik_values_yaml
}
