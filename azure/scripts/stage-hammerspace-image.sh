#!/usr/bin/env bash
# ============================================================
# stage-hammerspace-image.sh
#
# Run this ONCE, ahead of deployment, to copy a Hammerspace VHD
# (delivered by Hammerspace as a read-only blob SAS URL) into
# YOUR Azure subscription and wrap it in a managed image.
#
# Designed for Azure Cloud Shell (bash) - no local installs
# needed - but works anywhere the az CLI is logged in.
#
#   ./stage-hammerspace-image.sh \
#       -u "https://<acct>.blob.core.windows.net/.../<image>.vhd?sp=r&...&sig=..." \
#       -g <resource-group> [-l <location>] [-n <image-name>]
#
# The copy is SERVER-SIDE (Azure Storage pulls from the SAS URL);
# nothing large flows through this machine. When it finishes, the
# script prints the image ID to use as image_id in the Hammerspace
# Terraform (or ARM/marketplace "existing image" deployments).
# ============================================================
set -euo pipefail

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed -n '2,20p'; exit 1; }

SAS_URL="" RG="" LOCATION="" IMAGE_NAME="" SA_NAME="" DELETE_VHD="false" TAGS=""
while getopts "u:g:l:n:a:t:dh" opt; do
  case "$opt" in
    u) SAS_URL=$OPTARG ;;
    g) RG=$OPTARG ;;
    l) LOCATION=$OPTARG ;;
    n) IMAGE_NAME=$OPTARG ;;
    a) SA_NAME=$OPTARG ;;
    t) TAGS=$OPTARG ;;        # space-separated key=value tags for created resources
    d) DELETE_VHD="true" ;;   # delete the staged .vhd blob after the image is created
    *) usage ;;
  esac
done
[ -n "$SAS_URL" ] && [ -n "$RG" ] || usage

case "$SAS_URL" in
  https://*.vhd\?*) ;;
  *) echo "ERROR: -u must be an https blob SAS URL pointing at a .vhd (…/<image>.vhd?<sas-token>)"; exit 1 ;;
esac

BLOB_SRC_NAME=$(basename "${SAS_URL%%\?*}")
IMAGE_NAME=${IMAGE_NAME:-"${BLOB_SRC_NAME%.vhd}"}
CONTAINER="hammerspace-images"

# --- Idempotent: nothing to do when the image already exists ---
# (This is what makes Terraform apply/destroy cycles reuse the image
# instead of re-downloading the VHD.)
if EXISTING_ID=$(az image show --resource-group "$RG" --name "$IMAGE_NAME" --query id -o tsv 2>/dev/null); then
  cat <<EOF1

============================================================
Image already staged - nothing to do.

  image_id = "$EXISTING_ID"
============================================================
EOF1
  exit 0
fi

# --- Resource group (created if missing; -l required in that case) ---
if [ "$(az group exists --name "$RG")" != "true" ]; then
  [ -n "$LOCATION" ] || { echo "ERROR: resource group $RG does not exist - pass -l <location> to create it."; exit 1; }
  echo ">> Creating resource group $RG in $LOCATION"
  az group create --name "$RG" --location "$LOCATION" --output none
else
  LOCATION=${LOCATION:-$(az group show --name "$RG" --query location -o tsv)}
fi

# --- Staging storage account (name must be globally unique) ---
if [ -z "$SA_NAME" ]; then
  SA_NAME="hsimg$(echo "$RG$LOCATION" | sha1sum | cut -c1-16)"
fi
if ! az storage account show --name "$SA_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  echo ">> Creating storage account $SA_NAME"
  # shellcheck disable=SC2086  # TAGS is deliberately word-split into key=value pairs
  az storage account create --name "$SA_NAME" --resource-group "$RG" \
    --location "$LOCATION" --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false \
    ${TAGS:+--tags $TAGS} --output none
fi
KEY=$(az storage account keys list --account-name "$SA_NAME" --resource-group "$RG" --query '[0].value' -o tsv)
az storage container create --name "$CONTAINER" \
  --account-name "$SA_NAME" --account-key "$KEY" --output none

# --- Server-side copy (skipped/resumed if a previous run staged the blob) ---
BLOB_STATUS=$(az storage blob show --account-name "$SA_NAME" --account-key "$KEY" \
  --container-name "$CONTAINER" --name "$BLOB_SRC_NAME" \
  --query 'properties.copy.status' -o tsv 2>/dev/null || true)
case "$BLOB_STATUS" in
  success) echo ">> Blob already staged - skipping copy" ;;
  pending) echo ">> A previous copy is still running - waiting for it" ;;
  *)
    echo ">> Starting server-side copy of $BLOB_SRC_NAME (nothing flows through this machine)"
    az storage blob copy start \
      --account-name "$SA_NAME" --account-key "$KEY" \
      --destination-container "$CONTAINER" --destination-blob "$BLOB_SRC_NAME" \
      --source-uri "$SAS_URL" --output none ;;
esac

echo ">> Waiting for the copy to finish (Ctrl-C is safe - the copy continues server-side)"
while :; do
  read -r STATUS PROGRESS <<EOF2
$(az storage blob show --account-name "$SA_NAME" --account-key "$KEY" \
    --container-name "$CONTAINER" --name "$BLOB_SRC_NAME" \
    --query '[properties.copy.status, properties.copy.progress]' -o tsv)
EOF2
  case "$STATUS" in
    success) echo "   copy complete (${PROGRESS:-done})"; break ;;
    pending)
      DONE=${PROGRESS%%/*}; TOTAL=${PROGRESS##*/}
      [ "${TOTAL:-0}" -gt 0 ] 2>/dev/null && echo "   ${DONE} / ${TOTAL} bytes ($(( DONE * 100 / TOTAL ))%)"
      sleep 15 ;;
    *) echo "ERROR: copy $STATUS - the SAS may be expired or IP-restricted (the source must be readable by Azure Storage, not just by this machine)."; exit 1 ;;
  esac
done

# --- Managed image (independent of the blob once created) ---
BLOB_URL="https://${SA_NAME}.blob.core.windows.net/${CONTAINER}/${BLOB_SRC_NAME}"
echo ">> Creating managed image $IMAGE_NAME"
# shellcheck disable=SC2086
az image create --resource-group "$RG" --name "$IMAGE_NAME" --location "$LOCATION" \
  --os-type Linux --hyper-v-generation V1 --source "$BLOB_URL" \
  ${TAGS:+--tags $TAGS} --output none
IMAGE_ID=$(az image show --resource-group "$RG" --name "$IMAGE_NAME" --query id -o tsv)

if [ "$DELETE_VHD" = "true" ]; then
  echo ">> Deleting the staged .vhd blob (image keeps its own copy)"
  az storage blob delete --account-name "$SA_NAME" --account-key "$KEY" \
    --container-name "$CONTAINER" --name "$BLOB_SRC_NAME" --output none
fi

cat <<EOF3

============================================================
DONE. Use this image in the Hammerspace deployment:

  image_id = "$IMAGE_ID"

(The staged .vhd blob in $SA_NAME/$CONTAINER can be deleted to
save storage cost$( [ "$DELETE_VHD" = "true" ] && echo " - already deleted (-d)" ); the image does not depend on it.)
============================================================
EOF3
