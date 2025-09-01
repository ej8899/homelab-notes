#!/usr/bin/env bash
# benchscore.sh — single-number CPU score (sysbench events/sec)
set -euo pipefail

# Install sysbench if missing (Debian/Ubuntu/Proxmox)
if ! command -v sysbench >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq sysbench >/dev/null 2>&1 || true
  fi
fi

# If still missing, bail with 0 (so it won't break your compare)
if ! command -v sysbench >/dev/null 2>&1; then
  echo "$(hostname -s),BENCHSCORE=0"
  exit 0
fi

# Run a short CPU test on all cores
RAW=$(sysbench cpu --threads="$(nproc)" --time=15 run 2>/dev/null || true)

# Pull the "events per second" number robustly
SCORE=$(echo "$RAW" | awk -F: '/events per second/ {gsub(/ /,""); print $2; exit}')

# Fallback if parsing failed
if [[ -z "${SCORE:-}" ]]; then SCORE=0; fi

echo "$(hostname -s),BENCHSCORE=${SCORE}"
