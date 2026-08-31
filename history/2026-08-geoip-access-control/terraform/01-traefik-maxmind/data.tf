data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  for_each = local.public_subnets
  id       = each.value
}

data "aws_route53_zone" "this" {
  zone_id      = var.hosted_zone_id
  private_zone = false
}

check "eks_cluster_belongs_to_vpc" {
  assert {
    condition     = data.aws_eks_cluster.this.vpc_config[0].vpc_id == var.vpc_id
    error_message = "cluster_name must identify an EKS cluster in vpc_id."
  }
}

check "public_subnets_belong_to_vpc" {
  assert {
    condition     = alltrue([for subnet in data.aws_subnet.public : subnet.vpc_id == var.vpc_id])
    error_message = "Every public subnet must belong to vpc_id."
  }
}

check "public_subnets_span_availability_zones" {
  assert {
    condition     = length(distinct([for subnet in data.aws_subnet.public : subnet.availability_zone])) == length(var.public_subnet_ids)
    error_message = "public_subnet_ids must use distinct Availability Zones."
  }
}

check "certificate_is_regional" {
  assert {
    condition     = startswith(var.certificate_arn, "arn:${data.aws_partition.current.partition}:acm:${var.aws_region}:")
    error_message = "certificate_arn must identify an ACM certificate in aws_region."
  }
}

check "hosts_are_confined_to_the_poc_zone" {
  assert {
    condition = alltrue([
      for host in local.all_hosts :
      endswith(host, var.required_poc_dns_suffix) &&
      endswith("${host}.", "${trimsuffix(lower(data.aws_route53_zone.this.name), ".")}.")
    ])
    error_message = "Every PoC host must use required_poc_dns_suffix and belong to hosted_zone_id."
  }
}

check "control_host_is_not_protected" {
  assert {
    condition     = !contains(var.protected_hosts, var.control_host)
    error_message = "control_host must stay outside protected_hosts so it can serve as the negative control."
  }
}
