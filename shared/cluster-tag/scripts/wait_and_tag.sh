#!/usr/bin/env bash
# Wait for the cluster management API, read the cluster ID (cntl uoid.uuid),
# then run $TAG_COMMAND with __CLUSTER_ID__ replaced by the real ID.
# Env: HS_ENDPOINT HS_USER HS_PASSWORD HS_WAIT_RETRIES HS_RETRIES HS_DELAY
#      TAG_COMMAND
set -u

base="https://${HS_ENDPOINT}:8443/mgmt/v1.2/rest"

# Credentials go in a 0600 config file, not in -u on the command line: argv is
# world-readable through ps(1) on the machine running terraform, and the loops
# below re-run curl for up to ${HS_WAIT_RETRIES} + ${HS_RETRIES} attempts.
# Backslash and double quote are escaped because curl unescapes them inside a
# quoted config value - the same two-layer quoting that bit the Azure module.
cfg=$(mktemp)
trap 'rm -f "${cfg}"' EXIT
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
( umask 077; printf 'user = "%s:%s"\n' "$(esc "${HS_USER}")" "$(esc "${HS_PASSWORD}")" > "${cfg}" )

# Readiness wait - the equivalent of the Ansible "Query Anvil API" task that
# always precedes the tag role (120 x 10s = 20 minutes by default).
echo "Waiting for the cluster management API at ${base}/sites/local ..."
ready=""
for ((i = 1; i <= HS_WAIT_RETRIES; i++)); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 \
    -K "${cfg}" "${base}/sites/local" || true)
  if [[ "${code}" == "200" ]]; then
    ready=yes
    break
  fi
  sleep "${HS_DELAY}"
done
if [[ -z "${ready}" ]]; then
  echo "ERROR: cluster management API did not answer 200 within $((HS_WAIT_RETRIES * HS_DELAY))s." >&2
  exit 1
fi

cluster_id=""
for ((i = 1; i <= HS_RETRIES; i++)); do
  body=$(curl -sk --max-time 15 -K "${cfg}" "${base}/cntl" || true)
  if [[ -n "${body}" ]]; then
    cluster_id=$(printf '%s' "${body}" | python3 -c \
      'import json,sys
try:
    print(json.load(sys.stdin)[0]["uoid"]["uuid"])
except Exception:
    pass' || true)
    [[ -n "${cluster_id}" ]] && break
  fi
  sleep "${HS_DELAY}"
done

if [[ -z "${cluster_id}" ]]; then
  echo "ERROR: could not read the cluster ID from ${base}/cntl after ${HS_RETRIES} attempts." >&2
  exit 1
fi

# Basic sanity: the ID lands inside a shell command line.
if [[ ! "${cluster_id}" =~ ^[A-Za-z0-9-]+$ ]]; then
  echo "ERROR: unexpected cluster ID format: ${cluster_id}" >&2
  exit 1
fi

# The exit status of eval MUST be checked. Without this the script's status was
# that of the echo below - always 0 - so a tagging command that failed (expired
# credentials, a missing ec2:CreateTags / Microsoft.Resources/tags permission, a
# VM deleted underneath us) was reported to terraform as a clean apply, and the
# log affirmatively claimed the instances were tagged when they were not.
#
# Callers must join multi-command TAG_COMMANDs with && rather than ; - with ;
# only the LAST command's status survives, so a failure in any earlier one would
# still be invisible here.
cmd="${TAG_COMMAND//__CLUSTER_ID__/${cluster_id}}"
if ! eval "${cmd}"; then
  echo "ERROR: tagging failed for cluster ID ${cluster_id}. The nodes are deployed and healthy but carry no cluster-ID tag; fix the cause and re-apply." >&2
  exit 1
fi
echo "Tagged deployment with cluster ID ${cluster_id}"
