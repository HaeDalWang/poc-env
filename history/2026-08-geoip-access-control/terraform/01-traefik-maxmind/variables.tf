# ---------------------------------------------------------------------------
# Target cluster and network
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region hosting the PoC cluster"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Short ASCII name prefixed to every option 1 resource"
  type        = string
  default     = "geoip-opt1"
}

variable "cluster_name" {
  description = "Existing EKS cluster name that receives the option 1 workload"
  type        = string
}

variable "vpc_id" {
  description = "VPC containing the EKS cluster and the PoC NLB"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs used by the PoC NLB, one per Availability Zone"
  type        = list(string)

  validation {
    condition = (
      length(var.public_subnet_ids) >= 2 &&
      length(var.public_subnet_ids) <= 4 &&
      length(distinct(var.public_subnet_ids)) == length(var.public_subnet_ids)
    )
    error_message = "public_subnet_ids must contain 2-4 distinct subnet IDs."
  }
}

variable "namespace" {
  description = "Dedicated Kubernetes namespace for option 1"
  type        = string
  default     = "geoip-opt1"
}

# ---------------------------------------------------------------------------
# Ingress identity
# ---------------------------------------------------------------------------

variable "certificate_arn" {
  description = "Regional ACM certificate covering protected_hosts and control_host"
  type        = string
}

variable "hosted_zone_id" {
  description = "Public Route53 hosted zone that owns the PoC hostnames"
  type        = string
}

variable "protected_hosts" {
  description = "Hosts whose SMS route is guarded by the MaxMind country gate"
  type        = list(string)
  default     = ["geoip-opt1.seungdobae.com"]

  validation {
    condition = (
      length(var.protected_hosts) >= 1 && length(var.protected_hosts) <= 2 &&
      length(distinct(var.protected_hosts)) == length(var.protected_hosts) &&
      alltrue([
        for host in var.protected_hosts :
        host == lower(host) && !startswith(host, "http") && !strcontains(host, ":")
      ])
    )
    error_message = "protected_hosts must contain 1-2 distinct lowercase DNS names without scheme or port."
  }
}

variable "control_host" {
  description = <<-DESC
    Unprotected control hostname served by the same entrypoint and backend.
    It proves that the middleware chain applies only to the protected route,
    which cannot be shown with a 404 from an unrouted host.
  DESC
  type        = string
  default     = "geoip-opt1-control.seungdobae.com"

  validation {
    condition     = var.control_host == lower(var.control_host) && !strcontains(var.control_host, ":")
    error_message = "control_host must be a lowercase DNS name without a port."
  }
}

variable "required_poc_dns_suffix" {
  description = "Safety suffix every PoC hostname must end with"
  type        = string
  default     = ".seungdobae.com"
}

variable "create_dns_records" {
  description = "Create Route53 alias records once the NLB reports healthy targets"
  type        = bool
  default     = false
}

variable "allowed_ipv4_cidrs" {
  description = "Test-source IPv4 CIDRs allowed to reach the PoC NLB"
  type        = set(string)

  validation {
    condition = (
      length(var.allowed_ipv4_cidrs) >= 1 &&
      alltrue([
        for cidr in var.allowed_ipv4_cidrs :
        can(cidrnetmask(cidr)) && tonumber(split("/", cidr)[1]) >= 24
      ])
    )
    error_message = "allowed_ipv4_cidrs must contain IPv4 CIDRs with a /24 or narrower prefix."
  }
}

# ---------------------------------------------------------------------------
# Policy scope under test
# ---------------------------------------------------------------------------

variable "protected_scope" {
  description = <<-DESC
    Which requests the country gate guards.
      wsdl_only : Path(`/SMS.asmx`) && Query(`WSDL`)  - the customer's literal ask.
                  Traefik v3 matches this only when WSDL carries an empty value,
                  so `?WSDL=1`, `?wsdl` and bodyless POSTs bypass the gate.
      path_all  : PathPrefix(`/SMS.asmx`) - every method and query on the SMS path.
    Run both to show the customer what the narrow scope leaves open.
  DESC
  type        = string
  default     = "wsdl_only"

  validation {
    condition     = contains(["wsdl_only", "path_all"], var.protected_scope)
    error_message = "protected_scope must be wsdl_only or path_all."
  }
}

variable "allowed_country_codes" {
  description = "ISO country codes accepted by the header gate"
  type        = list(string)
  default     = ["KR"]

  validation {
    condition = (
      length(var.allowed_country_codes) >= 1 &&
      alltrue([for code in var.allowed_country_codes : can(regex("^[A-Z]{2}$", code))])
    )
    error_message = "allowed_country_codes must contain uppercase two-letter ISO codes."
  }
}

# ---------------------------------------------------------------------------
# Pinned component versions
# ---------------------------------------------------------------------------

variable "traefik_chart_version" {
  description = "Traefik Helm chart version, matching the customer deployment"
  type        = string
  default     = "39.0.0"
}

variable "traefik_image_tag" {
  description = "Traefik image tag and digest. The chart splits on @ for version detection."
  type        = string
  default     = "v3.6.7@sha256:a9890c898f379c1905ee5b28342f6b408dc863f08db2dab20e46c267d1ff463a"
}

variable "traefik_replicas" {
  description = "Traefik replica count"
  type        = number
  default     = 2
}

variable "geoip2_plugin_version" {
  description = "Pinned traefik-plugins/traefikgeoip2 version"
  type        = string
  default     = "v0.22.0"
}

variable "checkheaders_plugin_version" {
  description = "Pinned dkijkuit/checkheadersplugin version"
  type        = string
  default     = "v0.3.1"
}

variable "echo_image" {
  description = "Request echo image that reflects received headers back to the caller"
  type        = string
  default     = "traefik/whoami:v1.11.0@sha256:200689790a0a0ea48ca45992e0450bc26ccab5307375b41c84dfc4f2475937ab"
}

variable "maxmind_geoipupdate_image" {
  description = "Official MaxMind geoipupdate image"
  type        = string
  default     = "ghcr.io/maxmind/geoipupdate:v8.0.0@sha256:51e70dd6f16cd3e4d845ac02d09940b10772a75b9d741427d235a78570923c1d"
}

# ---------------------------------------------------------------------------
# MaxMind credentials and database handling
# ---------------------------------------------------------------------------

variable "maxmind_account_id" {
  description = "MaxMind account ID. Supply through TF_VAR_maxmind_account_id, never in a committed file."
  type        = string
  sensitive   = true

  validation {
    condition     = var.simulate_missing_db || length(trimspace(var.maxmind_account_id)) > 0
    error_message = "maxmind_account_id is required unless simulate_missing_db is true."
  }
}

variable "maxmind_license_key" {
  description = "MaxMind license key. Supply through TF_VAR_maxmind_license_key, never in a committed file."
  type        = string
  sensitive   = true

  validation {
    condition     = var.simulate_missing_db || length(trimspace(var.maxmind_license_key)) > 0
    error_message = "maxmind_license_key is required unless simulate_missing_db is true."
  }
}

variable "maxmind_edition_id" {
  description = "MaxMind database edition. The plugin selects its reader by matching Country or City in the file name."
  type        = string
  default     = "GeoLite2-Country"

  validation {
    condition     = contains(["GeoLite2-Country", "GeoLite2-City"], var.maxmind_edition_id)
    error_message = "maxmind_edition_id must be GeoLite2-Country or GeoLite2-City."
  }
}

variable "db_refresh_interval_hours" {
  description = <<-DESC
    When greater than 0, a geoipupdate sidecar rewrites the database file on this
    interval. The plugin caches its reader in a package-level variable and never
    reopens the file, so this exists to measure that a refreshed file does not
    change verdicts - not to make refresh work.
  DESC
  type        = number
  default     = 0

  validation {
    condition     = var.db_refresh_interval_hours >= 0 && var.db_refresh_interval_hours <= 24
    error_message = "db_refresh_interval_hours must be between 0 and 24."
  }
}

variable "simulate_missing_db" {
  description = <<-DESC
    Skip the database download so Traefik starts with no MaxMind file.
    The plugin then stamps every request with country XX, which the header gate
    rejects. Set this to capture evidence for the fail-closed claim.
  DESC
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Additional AWS tags merged into the default tag set"
  type        = map(string)
  default     = {}
}
