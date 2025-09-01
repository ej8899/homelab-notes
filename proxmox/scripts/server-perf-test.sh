#!/usr/bin/env bash
# server-perf-test.sh
# Quick multi-node CPU spec & micro-benchmark runner for Proxmox/Debian/Ubuntu.
# Outputs results to ./cpu-bench-YYYYmmdd-HHMMSS.csv

set -euo pipefail

# ---------- Config ----------
SSH_USER="${SSH_USER:-root}"         # export SSH_USER if you don’t use root
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no"
SYSBENCH_TIME="${SYSBENCH_TIME:-20}" # seconds for sysbench cpu
OPENSSL_TIME="${OPENSSL_TIME:-10}"   # seconds per openssl test
PARALLEL_JOBS="${PARALLEL_JOBS:-0}"  # 0=serial; else number of parallel nodes
HOSTS_FILE=""                        # optional file with one host per line
INSTALL_MISSING=0                    # 1 to apt-get install sysbench/p7zip-full if missing (Debian/Ubuntu)
# -----------------------------

usage() {
  cat <<'EOF'
Usage:
  server-perf-test.sh [--hosts hosts.txt] [--install] [--parallel N]

If --hosts is omitted AND you're on a Proxmox node, the script will auto-discover nodes from /etc/pve/nodes.
Environment overrides:
  SSH_USER=root SYSBENCH_TIME=20 OPENSSL_TIME=10 PARALLEL_JOBS=0
Examples:
  SSH_USER=root ./homelab-cpu-bench.sh --install
  ./homelab-cpu-bench.sh --hosts mynodes.txt --parallel 3
EOF
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS_FILE="$2"; shift 2 ;;
    --install) INSTALL_MISSING=1; shift ;;
    --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

timestamp() { date +"%Y%m%d-%H%M%S"; }
OUT_FILE="cpu-bench-$(timestamp).csv"

# Discover hosts
HOSTS=()
if [[ -n "$HOSTS_FILE" ]]; then
  mapfile -t HOSTS < <(grep -vE '^\s*#|^\s*$' "$HOSTS_FILE")
else
  if [[ -d /etc/pve/nodes ]]; then
    mapfile -t HOSTS < <(ls -1 /etc/pve/nodes 2>/dev/null | sort)
  else
    echo "No --hosts and not on a Proxmox node. Provide --hosts hosts.txt"
    exit 1
  fi
fi
if [[ ${#HOSTS[@]} -eq 0 ]]; then
  echo "No hosts found."; exit 1
fi

# CSV header
#echo "host,kernel,model,cores,threads,base_mhz,max_mhz,aes,avx2,avx512,sysbench_events_per_sec,openssl_sha256_kBps,openssl_aes256gcm_kBps,7z_mips" | tee "$OUT_FILE" >/dev/null
printf "%-12s %-18s %-28s %-5s %-7s %-8s %-8s %-3s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
  "host" "kernel" "model" "cores" "threads" "baseMHz" "maxMHz" "AES" "AVX2" "AVX512" \
  "sysbench/s" "openssl-SHA256" "openssl-AES256GCM" "7z-MIPS"
printf "%0.s-" {1..150}; echo

remote_sh() {
  local host="$1" cmd="$2"
  ssh $SSH_OPTS "${SSH_USER}@${host}" "$cmd"
}

prep_cmd='
set -e
detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
  echo "unknown"
}
OSPKG=$(detect_pkg)

# Optionally install tools (Debian/Ubuntu only by default)
if [[ '"$INSTALL_MISSING"' -eq 1 ]]; then
  if [[ "$OSPKG" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq sysbench p7zip-full >/dev/null 2>&1 || true
  fi
fi

# Gather specs
KERNEL=$(uname -r)
MODEL=$(lscpu | awk -F: "/Model name/ {sub(/^ */,\"\",\$2); print \$2; exit}")
CORES=$(lscpu | awk -F: "/^Core\\(s\\) per socket/ {gsub(/ /,\"\"); c=\$2} /^Socket\\(s\\)/ {gsub(/ /,\"\"); s=\$2} END{if(c==\"\") c=1; if(s==\"\") s=1; print c*s}")
THREADS=$(lscpu | awk -F: "/^CPU\\(s\\)/ {gsub(/ /,\"\"); print \$2; exit}")
BASE_MHZ=$(lscpu | awk -F: "/^CPU MHz:/ {sub(/^ */,\"\",\$2); print int(\$2); exit}")
MAX_MHZ=$(lscpu | awk -F: "/^CPU max MHz:/ {sub(/^ */,\"\",\$2); print int(\$2); exit}")
FLAGS=$(lscpu | awk -F: "/^Flags:/ {print \$2; exit}")

hasflag() { echo "$FLAGS" | grep -qw "$1" && echo yes || echo no; }
AES=$(hasflag aes)
AVX2=$(hasflag avx2)
AVX512=$(hasflag avx512f)

# sysbench cpu
SB_EPS=""
if command -v sysbench >/dev/null 2>&1; then
  RAW=$(sysbench cpu --threads=$(nproc) --time='"$SYSBENCH_TIME"' run 2>/dev/null || true)
  SB_EPS=$(echo "$RAW" | awk -F: "/events per second/ {gsub(/ /,\"\"); print \$2; exit}")
fi

# openssl speed (sha256 & aes-256-gcm) in kB/s
OS_SHA=""
OS_AES=""
if command -v openssl >/dev/null 2>&1; then
  # SHA256: take 8192-byte line, last column is kB/s
  SHA=$(openssl speed -elapsed -seconds '"$OPENSSL_TIME"' -multi $(nproc) sha256 2>/dev/null || true)
  OS_SHA=$(echo "$SHA" | awk "/^sha256 / && /8192 bytes/ {print \$NF; exit}")
  # AES-256-GCM (evp)
  AESOUT=$(OPENSSL_ia32cap=~0 openssl speed -elapsed -seconds '"$OPENSSL_TIME"' -multi $(nproc) -evp aes-256-gcm 2>/dev/null || true)
  OS_AES=$(echo "$AESOUT" | awk "/^aes-256-gcm *evp/ {kbps=\$NF} END{print kbps}")
fi

# 7zip benchmark MIPS (optional if p7zip-full present)
SEVENZ=""
if command -v 7z >/dev/null 2>&1; then
  # -bso0 (no stdout), -bsp1 (progress to stdout); capture the "Total" MIPS
  B=$(7z b -mmt=$(nproc) -bso0 -bsp1 2>/dev/null || true)
  SEVENZ=$(echo "$B" | awk -F= "/^Total:/ {print \$2; exit}" | tr -d " ")
fi

echo "$KERNEL|$MODEL|$CORES|$THREADS|$BASE_MHZ|$MAX_MHZ|$AES|$AVX2|$AVX512|$SB_EPS|$OS_SHA|$OS_AES|$SEVENZ"
'

run_one() {
  local host="$1"
  # quick reachable check
  if ! ssh $SSH_OPTS "${SSH_USER}@${host}" "echo ok" >/dev/null 2>&1; then
    echo "WARN: cannot reach $host" >&2
    echo "$host,unreachable,,,,,,,,,,," | tee -a "$OUT_FILE" >/dev/null
    return
  fi
  IFS="|" read -r KERNEL MODEL CORES THREADS BASE_MHZ MAX_MHZ AES AVX2 AVX512 SB_EPS OS_SHA OS_AES SEVENZ < <(remote_sh "$host" "$prep_cmd")

  # CSV escape: replace commas in model
  MODEL_CSV=$(echo "$MODEL" | tr ',' ';')
  #echo "$host,$KERNEL,$MODEL_CSV,$CORES,$THREADS,$BASE_MHZ,$MAX_MHZ,$AES,$AVX2,$AVX512,$SB_EPS,$OS_SHA,$OS_AES,$SEVENZ" | tee -a "$OUT_FILE" >/dev/null
  printf "%-12s %-18s %-28s %-5s %-7s %-8s %-8s %-3s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
  "$host" "$KERNEL" "${MODEL:0:27}" "$CORES" "$THREADS" "$BASE_MHZ" "$MAX_MHZ" "$AES" \
  "$AVX2" "$AVX512" "$SB_EPS" "$OS_SHA" "$OS_AES" "$SEVENZ"
}

export -f run_one
export SSH_USER SSH_OPTS OUT_FILE prep_cmd SYSBENCH_TIME OPENSSL_TIME INSTALL_MISSING

echo "Running on ${#HOSTS[@]} host(s)..."
if [[ "$PARALLEL_JOBS" -gt 0 ]]; then
  # requires xargs -P (GNU)
  printf "%s\n" "${HOSTS[@]}" | xargs -n1 -P "$PARALLEL_JOBS" -I{} bash -c 'run_one "$@"' _ {}
else
  for h in "${HOSTS[@]}"; do run_one "$h"; done
fi

echo "Done. Results saved to $OUT_FILE"
