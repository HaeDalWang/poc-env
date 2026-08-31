data "aws_partition" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)
  id       = each.value
}

data "aws_security_group" "traefik_target" {
  id = var.traefik_target_security_group_id
}

data "aws_route53_zone" "this" {
  zone_id = var.hosted_zone_id
}

data "aws_caller_identity" "current" {}

check "subnets_belong_to_vpc" {
  assert {
    condition = (
      alltrue([for subnet in data.aws_subnet.public : subnet.vpc_id == var.vpc_id]) &&
      alltrue([for subnet in data.aws_subnet.private : subnet.vpc_id == var.vpc_id])
    )
    error_message = "Every public and private subnet must belong to vpc_id."
  }
}

check "subnets_span_availability_zones" {
  assert {
    condition = (
      length(distinct([for subnet in data.aws_subnet.public : subnet.availability_zone])) >= 2 &&
      length(distinct([for subnet in data.aws_subnet.private : subnet.availability_zone])) >= 2
    )
    error_message = "Public and private subnets must each span at least two availability zones."
  }
}

check "private_subnet_cidrs_match" {
  assert {
    condition     = toset(var.private_subnet_cidrs) == toset([for subnet in data.aws_subnet.private : subnet.cidr_block])
    error_message = "private_subnet_cidrs must exactly match the CIDRs of private_subnet_ids."
  }
}

check "target_security_group_belongs_to_vpc" {
  assert {
    condition     = data.aws_security_group.traefik_target.vpc_id == var.vpc_id
    error_message = "traefik_target_security_group_id must belong to vpc_id."
  }
}

check "eks_cluster_belongs_to_vpc" {
  assert {
    condition     = data.aws_eks_cluster.this.vpc_config[0].vpc_id == var.vpc_id
    error_message = "cluster_name must identify an EKS cluster in vpc_id."
  }
}

check "target_security_group_change_is_acknowledged" {
  assert {
    condition     = var.acknowledge_target_security_group_change
    error_message = "Review the target SG change and set acknowledge_target_security_group_change=true before deployment."
  }
}

check "certificate_is_regional" {
  assert {
    condition     = startswith(var.certificate_arn, "arn:${data.aws_partition.current.partition}:acm:${var.aws_region}:")
    error_message = "certificate_arn must be an ACM certificate in aws_region."
  }
}

check "protected_hosts_belong_to_zone" {
  assert {
    condition = alltrue([
      for host in var.protected_hosts :
      endswith("${host}.", "${trimsuffix(lower(data.aws_route53_zone.this.name), ".")}.")
    ])
    error_message = "Every protected host must belong to hosted_zone_id."
  }
}


check "protected_hosts_use_poc_suffix" {
  assert {
    condition = alltrue([
      for host in var.protected_hosts :
      endswith(host, var.required_poc_dns_suffix)
    ])
    error_message = "Every protected host must end with required_poc_dns_suffix."
  }
}
