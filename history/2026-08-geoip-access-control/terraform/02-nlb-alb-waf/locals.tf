locals {
  name = substr(
    trim(replace(lower(var.project_name), "/[^a-z0-9-]/", "-"), "-"),
    0,
    20
  )

  namespace_name      = var.namespace
  traefik_fullname    = "${local.name}-traefik"
  echo_name           = "${local.name}-echo"
  traefik_target_port = 8000
  echo_target_port    = 8080

  public_subnets = toset(var.public_subnet_ids)

  metric_prefix = replace(local.name, "-", "_")

  tags = merge(
    {
      Project     = local.name
      Environment = "poc"
      ManagedBy   = "Terraform"
      Purpose     = "GeoIP-WAF-Traefik-validation"
    },
    var.tags
  )
}
