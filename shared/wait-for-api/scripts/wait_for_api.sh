#!/usr/bin/env bash
# Wait until https://$HS_ENDPOINT:8443/mgmt/v1.2/rest/sites/local answers 200
# with the supplied credentials. Env: HS_ENDPOINT HS_USER HS_PASSWORD
# HS_RETRIES HS_DELAY.
set -u

url="https://${HS_ENDPOINT}:8443/mgmt/v1.2/rest/sites/local"
echo "Waiting for the cluster management API at ${url} (${HS_RETRIES} x ${HS_DELAY}s max) ..."

# Credentials go in a 0600 config file, not in -u on the command line: argv is
# world-readable through ps(1) on the machine running terraform, and this loop
# re-runs curl every ${HS_DELAY}s for up to ${HS_RETRIES} attempts.
# Backslash and double quote are escaped because curl unescapes them inside a
# quoted config value - the same two-layer quoting that bit the Azure module.
cfg=$(mktemp)
trap 'rm -f "${cfg}"' EXIT
esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
( umask 077; printf 'user = "%s:%s"\n' "$(esc "${HS_USER}")" "$(esc "${HS_PASSWORD}")" > "${cfg}" )

for ((i = 1; i <= HS_RETRIES; i++)); do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 \
    -K "${cfg}" "${url}" || true)
  if [[ "${code}" == "200" ]]; then
    echo "Cluster management API is up (attempt ${i})."
    exit 0
  fi
  sleep "${HS_DELAY}"
done

echo "ERROR: cluster management API at ${url} did not answer 200 within $((HS_RETRIES * HS_DELAY))s (last HTTP code: ${code})." >&2
exit 1
