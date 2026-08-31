variable "aws_region" {
  description = "AWS region for the isolated PoC"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Short ASCII name used for PoC resources"
  type        = string
  default     = "geoip-opt2"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "project_name must be 3-20 lowercase ASCII characters, digits, or hyphens."
  }
}

variable "cluster_name" {
  description = "Existing EKS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC that contains the EKS cluster and both load balancers"
  type        = string
}

variable "public_subnet_ids" {
  description = "Two or more public subnet IDs for the internet-facing NLB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2 && length(var.public_subnet_ids) <= 4 && length(distinct(var.public_subnet_ids)) == length(var.public_subnet_ids)
    error_message = "public_subnet_ids must contain 2-4 distinct subnet IDs."
  }
}

variable "private_subnet_ids" {
  description = "Two or more private subnet IDs for the internal ALB"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2 && length(var.private_subnet_ids) <= 4 && length(distinct(var.private_subnet_ids)) == length(var.private_subnet_ids)
    error_message = "private_subnet_ids must contain 2-4 distinct subnet IDs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs of private_subnet_ids; Traefik trusts forwarded headers only from these ALB subnets"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2 && alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "private_subnet_cidrs must contain valid CIDRs."
  }
}

variable "traefik_target_security_group_id" {
  description = "Security group attached to the Traefik Pod ENIs or worker nodes"
  type        = string
}

variable "acknowledge_target_security_group_change" {
  description = "Explicit acknowledgement that Terraform will add one ALB-to-Traefik rule to this existing target SG"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN covering every protected host"
  type        = string
}

variable "hosted_zone_id" {
  description = "Existing public Route53 hosted zone ID"
  type        = string
}

variable "protected_hosts" {
  description = "Dedicated PoC hosts protected by GeoMatch and managed reputation rules"
  type        = list(string)
  default = [
    "geoip-opt2.seungdobae.com",
  ]

  validation {
    condition = (
      length(var.protected_hosts) >= 1 && length(var.protected_hosts) <= 2 &&
      length(distinct(var.protected_hosts)) == length(var.protected_hosts) &&
      alltrue([
        for host in var.protected_hosts :
        host == lower(host) &&
        !startswith(host, "http") &&
        !strcontains(host, ":") &&
        length(split(".", host)) >= 3
      ])
    )
    error_message = "protected_hosts must contain 1-2 distinct lowercase DNS names without a scheme or port."
  }
}

variable "required_poc_dns_suffix" {
  description = "Safety suffix that all PoC hosts must use"
  type        = string
  default     = ".seungdobae.com"

  validation {
    condition     = startswith(var.required_poc_dns_suffix, ".") && length(split(".", var.required_poc_dns_suffix)) >= 3
    error_message = "required_poc_dns_suffix must be a dotted PoC DNS suffix."
  }
}

variable "create_dns_records" {
  description = "Create Route53 aliases only after target health and WAF association are reviewed"
  type        = bool
  default     = false
}

variable "allowed_ipv4_cidrs" {
  description = "IPv4 test-source CIDRs allowed to reach the frontend NLB; use explicit test runner CIDRs"
  type        = set(string)

  validation {
    condition = (
      length(var.allowed_ipv4_cidrs) >= 1 &&
      alltrue([
        for cidr in var.allowed_ipv4_cidrs :
        can(cidrnetmask(cidr)) && can(tonumber(split("/", cidr)[1]) >= 24)
      ])
    )
    error_message = "allowed_ipv4_cidrs must contain IPv4 CIDRs with a /24 or narrower prefix."
  }
}

variable "waf_mode" {
  description = "COUNT observes decisions; BLOCK enforces them after evidence review"
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], lower(var.waf_mode))
    error_message = "waf_mode must be count or block."
  }
}

variable "traefik_chart_version" {
  description = "Traefik chart version pinned to the customer reproduction baseline"
  type        = string
  default     = "39.0.0"
}

variable "traefik_replicas" {
  description = "Traefik replica count for rollout and readiness-gate tests"
  type        = number
  default     = 2

  validation {
    condition     = var.traefik_replicas >= 2 && var.traefik_replicas <= 10
    error_message = "traefik_replicas must be between 2 and 10."
  }
}

variable "namespace" {
  description = "Dedicated Kubernetes namespace for the PoC"
  type        = string
  default     = "geoip-opt2"
}

variable "ingress_class_name" {
  description = "Dedicated Traefik IngressClass name"
  type        = string
  default     = "traefik-geoip-opt2"
}

variable "echo_image" {
  description = "Pinned request echo image used to observe RemoteAddr and forwarded headers"
  type        = string
  default     = "traefik/whoami:v1.11.0@sha256:200689790a0a0ea48ca45992e0450bc26ccab5307375b41c84dfc4f2475937ab"
}

variable "traefik_image_tag" {
  description = "Traefik version and multi-architecture digest used by chart 39.0.0"
  type        = string
  default     = "v3.6.7@sha256:a9890c898f379c1905ee5b28342f6b408dc863f08db2dab20e46c267d1ff463a"
}

variable "waf_log_retention_days" {
  description = "Short retention for raw PoC WAF logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30], var.waf_log_retention_days)
    error_message = "waf_log_retention_days must be one of 1, 3, 5, 7, 14, or 30."
  }
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
