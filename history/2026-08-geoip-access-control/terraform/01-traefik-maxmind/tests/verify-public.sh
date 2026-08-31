#!/usr/bin/env bash
# Exercises the public NLB path and prints the verdict matrix.
#
# Every row states what it proves, so a surprising result is readable without
# rereading the Terraform. Run from the option 1 Terraform root after apply.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if ! command -v jq >/dev/null; then
  echo "jq is required" >&2
  exit 1
fi

readonly PROTECTED_HOST="$(terraform output -json protected_hosts | jq -r '.[0]')"
readonly CONTROL_HOST="$(terraform output -raw control_host)"
readonly EIP="${1:-$(terraform output -json nlb_eip_addresses | jq -r 'to_entries[0].value')}"

if [[ -z "${PROTECTED_HOST}" || -z "${EIP}" || "${EIP}" == "null" ]]; then
  echo "Could not read Terraform outputs. Apply first, or pass an EIP as \$1." >&2
  exit 1
fi

printf 'ingress   %s\n' "${EIP}"
printf 'protected %s\n' "${PROTECTED_HOST}"
printf 'control   %s\n\n' "${CONTROL_HOST}"

request() {
  local host="$1" path="$2"
  shift 2
  curl --silent --output /dev/null --write-out '%{http_code}' \
    --resolve "${host}:443:${EIP}" \
    --max-time 15 \
    "$@" \
    "https://${host}${path}"
}

row() {
  local id="$1" expectation="$2" actual="$3" meaning="$4"
  local mark="ok"
  [[ "${actual}" == "${expectation}" ]] || mark="DIFF"
  printf '%-5s %-6s %-6s %-4s %s\n' "${id}" "${expectation}" "${actual}" "${mark}" "${meaning}"
}

printf '%-5s %-6s %-6s %-4s %s\n' "id" "expect" "got" "" "what it proves"
printf '%s\n' "---------------------------------------------------------------------------"

row P1 200 "$(request "${PROTECTED_HOST}" '/SMS.asmx?WSDL')" \
  "domestic source reaches the guarded route"

row P2 200 "$(request "${PROTECTED_HOST}" '/SMS.asmx?WSDL' -H 'X-Forwarded-For: 8.8.8.8')" \
  "forged XFF does not change the country verdict"

row P3 200 "$(request "${PROTECTED_HOST}" '/observe')" \
  "observe route returns the verdict without blocking"

row P4 200 "$(request "${PROTECTED_HOST}" '/not-protected')" \
  "out-of-scope path on the same host is untouched"

row P5 200 "$(request "${CONTROL_HOST}" '/')" \
  "policy does not leak onto the control host"

row P6 404 "$(request "unrouted.seungdobae.com" '/SMS.asmx?WSDL')" \
  "unknown host matches no router"

printf '\n%s\n' "scope gaps - these SHOULD reach the gate but do not under wsdl_only:"
printf '%s\n' "---------------------------------------------------------------------------"

row S1 200 "$(request "${PROTECTED_HOST}" '/SMS.asmx?WSDL=1')" \
  "Query(WSDL) misses a valued parameter"

row S2 200 "$(request "${PROTECTED_HOST}" '/SMS.asmx?wsdl')" \
  "matcher is case sensitive"

row S3 200 "$(request "${PROTECTED_HOST}" '/SMS.asmx' -X POST -d '')" \
  "the actual SOAP call carries no query string at all"

printf '\nverdict headers on the observe route:\n'
curl --silent --resolve "${PROTECTED_HOST}:443:${EIP}" --max-time 15 \
  "https://${PROTECTED_HOST}/observe" | grep -i 'X-Geoip2' || echo '  (no X-GeoIP2 headers returned)'
