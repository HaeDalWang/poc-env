locals {
  name           = substr(var.project_name, 0, 20)
  namespace_name = var.namespace

  traefik_release     = "${local.name}-traefik"
  echo_name           = "${local.name}-echo"
  maxmind_secret_name = "${local.name}-maxmind"

  public_subnets   = { for subnet_id in var.public_subnet_ids : subnet_id => subnet_id }
  nlb_source_cidrs = [for subnet_id in var.public_subnet_ids : data.aws_subnet.public[subnet_id].cidr_block]

  # The in-cluster replay entrypoint only trusts PROXY headers written from inside the VPC.
  vpc_cidr_blocks = [for association in data.aws_vpc.this.cidr_block_associations : association.cidr_block]

  all_hosts           = concat(var.protected_hosts, [var.control_host])
  protected_host_rule = join(" || ", [for host in var.protected_hosts : "Host(`${host}`)"])

  # wsdl_only reproduces the customer's literal request. Traefik's one-argument
  # Query matcher only fires when the key carries an empty value, which is exactly
  # the gap the test matrix has to expose.
  scope_rules = {
    wsdl_only = "Path(`/SMS.asmx`) && Query(`WSDL`)"
    path_all  = "PathPrefix(`/SMS.asmx`)"
  }

  protected_rule = "(${local.protected_host_rule}) && ${local.scope_rules[var.protected_scope]}"
  observe_rule   = "(${local.protected_host_rule}) && PathPrefix(`/observe`)"
  baseline_rule  = "(${local.protected_host_rule}) && PathPrefix(`/`)"
  control_rule   = "Host(`${var.control_host}`) && PathPrefix(`/`)"

  geoip_db_path = "/geoip2/${var.maxmind_edition_id}.mmdb"
  echo_url      = "http://${local.echo_name}.${local.namespace_name}.svc.cluster.local:80"

  entrypoints = ["web", "pptest"]

  tags = merge(
    {
      Project     = local.name
      Environment = "poc"
      ManagedBy   = "Terraform"
      Purpose     = "GeoIP-option1-validation"
    },
    var.tags
  )
}
