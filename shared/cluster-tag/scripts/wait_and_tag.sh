#!/usr/bin/env bash
# Wait for the cluster management API, read the cluster ID (cntl uoid.uuid),
# then run $TAG_COMMAND with __CLUSTER_ID__ replaced by the real ID.
# Env: HS_ENDPOINT HS_USER HS_PASSWORD HS_WAIT_RETRIES HS_RETRIES HS_DELAY
#      TAG_COMMAND
set -u

base="https://${HS_ENDPOINT}:8443/mgmt/v1.2/rest"

# Readiness wait - the equivalent of the Ansible "Query Anvil API" task that
# always precedes the tag role (120 x 10s = 20 minutes by default).
echo "Waiting for the cluster management API at ${base}/sites/local ..."
ready=""
for ((i = 1; i <= HS_WAIT_RETRIES; i++)); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "${HS_USER}:${HS_PASSWORD}" "${base}/sites/local" || true)
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
  body=$(curl -sk --max-time 15 -u "${HS_USER}:${HS_PASSWORD}" "${base}/cntl" || true)
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

cmd="${TAG_COMMAND//__CLUSTER_ID__/${cluster_id}}"
eval "${cmd}"
echo "Tagged deployment with cluster ID ${cluster_id}"
