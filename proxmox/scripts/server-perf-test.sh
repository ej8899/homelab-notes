#!/usr/bin/env bash
# node-quick-bench.sh — run on ONE node; no SSH needed
# Usage:
#   ./node-quick-bench.sh
#   ./node-quick-bench.sh --install   # apt install sysbench + p7zip-full if available
set -euo pipefail

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
  if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1; then echo yum; return; fi
  echo none
}
OSPKG=$(pkg)
if [[ $INSTALL -eq 1 && "$OSPKG" == "apt" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  # sysbench (CPU), p7zip (compression). Openssl is base on Proxmox/Debian.
  apt-get install -y -qq sysbench p7zip-full >/dev/null 2>&1 || true
fi

# --- Specs ---
KERNEL=$(uname -r)
MODEL=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)
[[ -z "${MODEL:-}" ]] && MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')
CORES=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,""); c=$2} /^Socket\(s\)/ {gsub(/ /,""); s=$2} END{if(c=="") c=1; if(s=="") s=1; print c*s}')
THREADS=$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/ {gsub(/ /,""); print $2; exit}')
CUR_MHZ=$(lscpu 2>/dev/null | sed -n 's/^CPU MHz:[[:space:]]*//p' | awk 'NR==1{print int($1)}')
MAX_MHZ=$(lscpu 2>/dev/null | sed -n 's/^CPU max MHz:[[:space:]]*//p' | awk 'NR==1{print int($1)}')
[[ -z "${CUR_MHZ:-}" ]] && CUR_MHZ=$(awk -F: '/cpu MHz/{print int($2); exit}' /proc/cpuinfo 2>/dev/null || echo "")
FLAGS=$(lscpu 2>/dev/null | sed -n 's/^Flags:[[:space:]]*//p')
has() { echo "$FLAGS" | grep -qw "$1" && echo yes || echo no; }
AES=$(has aes); AVX2=$(has avx2); AVX512=$(has avx512f)

# --- Bench: sysbench CPU (events/s) ---
SB_EPS="-"
if command -v sysbench >/dev/null 2>&1; then
  RAW=$(sysbench cpu --threads="$(nproc)" --time 15 run 2>/dev/null || true)
  SB_EPS=$(echo "$RAW" | awk -F: '/events per second/ {gsub(/ /,""); print $2; exit}')
  [[ -z "$SB_EPS" ]] && SB_EPS="-"
fi

# --- Bench: OpenSSL sha256 (kB/s) ---
OS_SHA="-"
if command -v openssl >/dev/null 2>&1; then
  # OpenSSL 1.1.x and 3.x print slightly differently; these catches both.
  SHA=$(openssl speed -elapsed -seconds 10 sha256 2>/dev/null || true)
  OS_SHA=$(echo "$SHA" | awk '/(^|\s)sha256(\s|\().*(8192 bytes|\(8192 bytes\))/ {print $NF}' | head -n1)
  [[ -z "$OS_SHA" ]] && OS_SHA="-"
fi

# --- Bench: OpenSSL AES-256-GCM via EVP (kB/s) ---
OS_AES="-"
if command -v openssl >/dev/null 2>&1; then
  AESO=$(OPENSSL_ia32cap=~0 openssl speed -elapsed -seconds 10 -multi "$(nproc)" -evp aes-256-gcm 2>/dev/null || true)
  OS_AES=$(echo "$AESO" | awk '/aes-256-gcm/ && /evp/ {v=$NF} END{print v}')
  [[ -z "$OS_AES" ]] && OS_AES="-"
fi

# --- Bench: 7z MIPS (optional) ---
SEVENZ="-"
if command -v 7z >/dev/null 2>&1; then
  B=$(7z b -mmt="$(nproc)" -bso0 -bsp1 2>/dev/null || true)
  SEVENZ=$(echo "$B" | awk -F= '/^Total:/ {gsub(/ /,""); print $2; exit}')
  [[ -z "$SEVENZ" ]] && SEVENZ="-"
fi

# --- Pretty print (single row) ---
printf "%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
  "$(hostname -s)" "$KERNEL" "${MODEL:0:27}" "${CORES:-?}" "${THREADS:-?}" \
  "${CUR_MHZ:--}" "${MAX_MHZ:--}" "${AES:--}" "${AVX2:--}" "${AVX512:--}" \
  "${SB_EPS:--}" "${OS_SHA:--}" "${OS_AES:--}" "${SEVENZ:--}"
