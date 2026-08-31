#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

assert_file() {
  local path="$1"
  [[ -f "${root_dir}/${path}" ]] && pass "file exists: ${path}" || fail "missing file: ${path}"
}

assert_contains() {
  local path="$1" pattern="$2" description="$3"
  if [[ ! -f "${root_dir}/${path}" ]]; then
    fail "${description} (missing ${path})"
  elif rg --quiet "${pattern}" "${root_dir}/${path}"; then
    pass "${description}"
  else
    fail "${description}"
  fi
}

assert_not_contains() {
  local path="$1" pattern="$2" description="$3"
  if [[ ! -f "${root_dir}/${path}" ]]; then
    fail "${description} (missing ${path})"
  elif rg --quiet "${pattern}" "${root_dir}/${path}"; then
    fail "${description}"
  else
    pass "${description}"
  fi
}

for file in main.tf variables.tf data.tf locals.tf dns.tf outputs.tf terraform.tfvars.example \
  network.tf namespace.tf echo.tf dynamic-config.tf traefik.tf traefik-containers.tf pptest-service.tf \
  README.md tests/pp2.py tests/verify-public.sh tests/verify-incluster.sh; do
  assert_file "01-traefik-maxmind/${file}"
done

for file in main.tf variables.tf data.tf locals.tf kubernetes.tf dns.tf outputs.tf terraform.tfvars.example; do
  assert_file "02-nlb-alb-waf/${file}"
done

assert_file "02-nlb-alb-waf/load-balancers.tf"
assert_file "02-nlb-alb-waf/waf.tf"

# Option 1 assertions encode facts verified against pinned upstream sources.
# Each one names the source, so a future version bump that breaks the assumption
# is caught here rather than in a misread PoC result.

assert_contains 01-traefik-maxmind/main.tf 'version[[:space:]]*=[[:space:]]*"6\.60\.0"' \
  "option 1 pins the AWS provider"
assert_contains 01-traefik-maxmind/traefik.tf 'oci://ghcr\.io/traefik/helm' \
  "option 1 uses the official Traefik OCI chart"
assert_contains 01-traefik-maxmind/traefik.tf 'github\.com/traefik-plugins/traefikgeoip2' \
  "option 1 installs the MaxMind GeoIP2 plugin"
assert_contains 01-traefik-maxmind/traefik.tf 'github\.com/dkijkuit/checkheadersplugin' \
  "option 1 installs the blocking header plugin"

# traefikgeoip2 v0.22.0 types.go: CountryHeader = "X-GeoIP2-Country".
assert_contains 01-traefik-maxmind/dynamic-config.tf 'X-GeoIP2-Country' \
  "option 1 gates on the header the plugin actually emits"
# middleware.go getClientIP: RemoteAddr unless this is true.
assert_contains 01-traefik-maxmind/dynamic-config.tf 'preferXForwardedForHeader[[:space:]]*=[[:space:]]*false' \
  "option 1 judges on the restored connection address, not client-supplied XFF"

# A 403 alone cannot separate "foreign source" from "source never read", so the
# observe router and the address header must both survive refactors.
assert_contains 01-traefik-maxmind/dynamic-config.tf 'sms-observe' \
  "option 1 keeps a non-blocking route that reports the verdict"
assert_contains 01-traefik-maxmind/traefik.tf '"X-GeoIP2-IPAddress"[[:space:]]*=[[:space:]]*"keep"' \
  "option 1 logs which address the plugin judged"

# traefik-helm-chart v39.0.0 _podtemplate.tpl reads lowercase defaultmode.
assert_contains 01-traefik-maxmind/traefik.tf 'defaultmode' \
  "option 1 uses the chart's lowercase access-log field key"
assert_not_contains 01-traefik-maxmind/traefik.tf 'defaultMode[[:space:]]*=[[:space:]]*"(keep|drop|redact)"' \
  "option 1 does not use a camelCase access-log key the chart would drop"

assert_contains 01-traefik-maxmind/traefik.tf 'abortOnPluginFailure[[:space:]]*=[[:space:]]*true' \
  "option 1 refuses to serve traffic when a plugin fails to load"
assert_contains 01-traefik-maxmind/traefik.tf 'aws-load-balancer-proxy-protocol' \
  "option 1 enables Proxy Protocol on the NLB"
assert_contains 01-traefik-maxmind/traefik.tf 'aws-load-balancer-eip-allocations' \
  "option 1 attaches fixed EIPs to the NLB"

# The replay entrypoint trusts a forged source address and must never be public.
assert_contains 01-traefik-maxmind/traefik.tf 'pptest' \
  "option 1 provides an in-cluster PROXY protocol replay entrypoint"
assert_contains 01-traefik-maxmind/pptest-service.tf 'ClusterIP' \
  "option 1 exposes the replay entrypoint only inside the cluster"

assert_contains 01-traefik-maxmind/locals.tf 'SMS\.asmx' \
  "option 1 scopes the guarded router to the SMS path"
assert_contains 01-traefik-maxmind/variables.tf 'path_all' \
  "option 1 can widen the scope beyond the WSDL query"
assert_contains 01-traefik-maxmind/variables.tf 'control_host' \
  "option 1 keeps an unprotected control host"

assert_contains 01-traefik-maxmind/variables.tf 'ghcr\.io/maxmind/geoipupdate' \
  "option 1 downloads the database with MaxMind's official updater"
assert_contains 01-traefik-maxmind/namespace.tf 'resource "kubernetes_secret_v1" "maxmind"' \
  "option 1 manages the MaxMind secret through Terraform, not a shell provisioner"
assert_not_contains 01-traefik-maxmind/terraform.tfvars.example '^maxmind_license_key' \
  "option 1 never puts the MaxMind key in a tfvars file"

# Option 2: preserve fixed EIPs while inserting an ALB/WAF before Traefik.
assert_contains 02-nlb-alb-waf/main.tf 'version[[:space:]]*=[[:space:]]*"6\.60\.0"' \
  "option 2 pins the AWS provider"
assert_contains 02-nlb-alb-waf/kubernetes.tf 'oci://ghcr\.io/traefik/helm' \
  "option 2 uses the official Traefik OCI chart"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'load_balancer_type[[:space:]]*=[[:space:]]*"network"' \
  "option 2 creates the fixed-IP NLB"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'load_balancer_type[[:space:]]*=[[:space:]]*"application"' \
  "option 2 creates the WAF-capable ALB"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'target_type[[:space:]]*=[[:space:]]*"alb"' \
  "option 2 makes the ALB an NLB target"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'resource "aws_lb_listener_rule" "nlb_health"' \
  "option 2 gives NLB HTTPS health checks a host-independent ALB path"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'matcher[[:space:]]*=[[:space:]]*"200-399"' \
  "option 2 accepts successful HTTPS health responses"
assert_contains 02-nlb-alb-waf/data.tf 'trimsuffix' \
  "option 2 normalizes the Route53 zone trailing dot"
assert_contains 01-traefik-maxmind/data.tf 'trimsuffix' \
  "option 1 normalizes the Route53 zone trailing dot"
assert_contains 02-nlb-alb-waf/waf.tf 'AWSManagedRulesAnonymousIpList' \
  "option 2 enables the anonymous-IP managed rule"
assert_contains 02-nlb-alb-waf/waf.tf 'AWSManagedRulesAmazonIpReputationList' \
  "option 2 enables AWS IP reputation"
assert_contains 02-nlb-alb-waf/waf.tf 'country_codes[[:space:]]*=[[:space:]]*\["KR"\]' \
  "option 2 identifies KR with GeoMatch"
assert_contains 02-nlb-alb-waf/waf.tf 'uri_path' \
  "option 2 scopes WAF inspection to the SMS path"
assert_contains 02-nlb-alb-waf/waf.tf 'query_string' \
  "option 2 scopes WAF inspection to the WSDL query"
assert_contains 02-nlb-alb-waf/load-balancers.tf 'host_header' \
  "option 2 routes only the protected hosts to Traefik"
assert_not_contains 02-nlb-alb-waf/waf.tf 'name[[:space:]]*=[[:space:]]*"host"' \
  "option 2 leaves host normalization to the dedicated ALB listener"
assert_contains 02-nlb-alb-waf/variables.tf 'default[[:space:]]*=[[:space:]]*"count"' \
  "option 2 starts WAF in count mode"
assert_contains 02-nlb-alb-waf/terraform.tfvars 'waf_mode[[:space:]]*=[[:space:]]*"block"' \
  "option 2 actual deployment enforces WAF blocking"

for option in 01-traefik-maxmind 02-nlb-alb-waf; do
  assert_contains "${option}/variables.tf" 'create_dns_records' \
    "${option} has an explicit DNS switch"
  assert_contains "${option}/variables.tf" 'default[[:space:]]*=[[:space:]]*false' \
    "${option} keeps DNS disabled initially"
  assert_not_contains "${option}/terraform.tfvars.example" 'arn:aws|([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9]{12}' \
    "${option} example contains no real account, ARN, or public IP"
done

if ((failures > 0)); then
  printf '\n%d contract test(s) failed.\n' "${failures}" >&2
  exit 1
fi

printf '\nAll two-option Terraform contract tests passed.\n'
