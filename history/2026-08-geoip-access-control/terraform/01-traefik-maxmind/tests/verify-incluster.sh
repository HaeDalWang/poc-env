#!/usr/bin/env bash
# Replays forged PROXY v2 sources against the pptest entrypoint from inside the
# cluster, which is how per-country verdicts are measured without overseas hosts.
#
# Usage: verify-incluster.sh [path] [ip,ip,...]

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

readonly CONTEXT="${KUBE_CONTEXT:-seungdobae}"
readonly NAMESPACE="$(terraform output -raw namespace 2>/dev/null || echo geoip-opt1)"
readonly ENDPOINT="$(terraform output -raw pptest_endpoint 2>/dev/null)"
readonly HOST="$(terraform output -json protected_hosts 2>/dev/null | jq -r '.[0]')"
readonly PATH_UNDER_TEST="${1:-/SMS.asmx?WSDL}"

# Public resolver addresses standing in for their registered countries. Confirm
# each one against the deployed database before treating a row as evidence.
readonly DEFAULT_SOURCES="168.126.63.1,164.124.101.2,8.8.8.8,114.114.114.114,210.130.1.1,10.0.0.1"
readonly SOURCES="${2:-${DEFAULT_SOURCES}}"

if [[ -z "${ENDPOINT}" || -z "${HOST}" ]]; then
  echo "Could not read Terraform outputs. Apply first." >&2
  exit 1
fi

echo "context   ${CONTEXT}"
echo "namespace ${NAMESPACE}"
echo

kubectl --context "${CONTEXT}" -n "${NAMESPACE}" run "pp2-$$" \
  --rm --stdin --restart=Never --quiet \
  --image=python:3.13-alpine \
  --command -- python - "${ENDPOINT}" "${HOST}" "${PATH_UNDER_TEST}" "${SOURCES}" \
  < tests/pp2.py
