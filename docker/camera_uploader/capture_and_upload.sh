#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   RTSP_URL        - rtsp://... for the camera
#   UPLOAD_URL      - https://ejmedia.ca/api-snowcam-upload.php
#   API_SECRET      - shared secret that PHP verifies
# Optional env:
#   INTERVAL_SECONDS - how often to capture (default 600s / 10min)
#   SNAPSHOT_FILE    - temp path inside container

if [[ -z "${RTSP_URL:-}" || -z "${UPLOAD_URL:-}" || -z "${API_SECRET:-}" ]]; then
  echo "[snowcam] ERROR: RTSP_URL, UPLOAD_URL, and API_SECRET must be set." >&2
  exit 1
fi

INTERVAL_SECONDS="${INTERVAL_SECONDS:-600}"
SNAPSHOT_FILE="${SNAPSHOT_FILE:-/tmp/snowcam-latest.jpg}"

echo "[snowcam] Starting capture loop. Interval=${INTERVAL_SECONDS}s"

while true; do
  NOW="$(date -Iseconds)"
  echo "[snowcam] ${NOW} - Capturing frame from RTSP..."

  # Capture a single frame
  ffmpeg -loglevel error -rtsp_transport tcp \
    -i "${RTSP_URL}" \
    -frames:v 1 \
    -vf "scale=800:-1" \
    -q:v 2 \
    -y "${SNAPSHOT_FILE}" || {
      echo "[snowcam] WARNING: ffmpeg capture failed, will retry next interval." >&2
      sleep "${INTERVAL_SECONDS}"
      continue
    }

  echo "[snowcam] ${NOW} - Uploading snapshot to ${UPLOAD_URL}..."

  # Upload the image
        HTTP_CODE=$(curl -sS -o /tmp/snowcam-upload-response.json -w "%{http_code}" \
          -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
          -H "Expect:" \
          -F "api_secret=${API_SECRET}" \
          -F "snapshot=@${SNAPSHOT_FILE};type=image/jpeg" \
          "${UPLOAD_URL}" || echo "000")

  if [[ "${HTTP_CODE}" != "200" ]]; then
    echo "[snowcam] WARNING: upload failed (HTTP ${HTTP_CODE}). Response:" >&2
    cat /tmp/snowcam-upload-response.json >&2 || true
  else
    echo "[snowcam] ${NOW} - Upload OK."
  fi

  sleep "${INTERVAL_SECONDS}"
done