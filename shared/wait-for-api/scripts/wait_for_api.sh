#!/usr/bin/env bash
# Wait until https://$HS_ENDPOINT:8443/mgmt/v1.2/rest/sites/local answers 200
# with the supplied credentials. Env: HS_ENDPOINT HS_USER HS_PASSWORD
# HS_RETRIES HS_DELAY.
set -u

url="https://${HS_ENDPOINT}:8443/mgmt/v1.2/rest/sites/local"
echo "Waiting for the cluster management API at ${url} (${HS_RETRIES} x ${HS_DELAY}s max) ..."

for ((i = 1; i <= HS_RETRIES; i++)); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "${HS_USER}:${HS_PASSWORD}" "${url}" || true)
  if [[ "${code}" == "200" ]]; then
    echo "Cluster management API is up (attempt ${i})."
    exit 0
  fi
  sleep "${HS_DELAY}"
done

echo "ERROR: cluster management API at ${url} did not answer 200 within $((HS_RETRIES * HS_DELAY))s (last HTTP code: ${code})." >&2
exit 1
