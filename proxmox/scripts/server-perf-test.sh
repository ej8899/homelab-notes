#!/usr/bin/env bash
# server-perf-test.sh — Multi-node CPU micro-bench (color table, "just use my ssh")
# Behavior:
#  - You list hosts below (IPs or names you already ssh to successfully).
#  - For the current host, runs locally (no ssh).
#  - For others, runs exactly like: ssh root@host "<bench one-liner>".
#  - Prints a colorized, aligned table. No CSV. No discovery unless you ask.
#  - Optional: --install tries apt install of sysbench & p7zip-full on Debian/Ubuntu.

set -euo pipefail

# ========= EDIT THIS =========
HOSTS=(
  "127.0.0.1"   # keep local
  "lab"
  "hypnoserver"
  "nimbus"
  "vginy"
  "NibblersNothings"
  # "192.168.1.10"
  # "nimbus.yourdomain.tld"
)
# =============================

# Defaults (override with env if you want)
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SYSBENCH_TIME="${SYSBENCH_TIME:-20}"   # seconds
OPENSSL_TIME="${OPENSSL_TIME:-10}"     # seconds
RUN_TIMEOUT="${RUN_TIMEOUT:-180}"      # seconds per node
PARALLEL_JOBS="${PARALLEL_JOBS:-0}"    # 0 = serial
AUTO_DISCOVER="${AUTO_DISCOVER:-0}"    # 1 to also append corosync ring0_addr
INSTALL_MISSING=0                      # set by --install
DEBUG="${DEBUG:-0}"

# ---------- Colors ----------
use_color=1; [ -t 1 ] || use_color=0; [ "${NO_COLOR:-}" = "1" ] && use_color=0
if [ "$use_color" -eq 1 ] && command -v tput >/dev/null 2>&1; then
  B=$(tput bold); D=$(tput dim); R=$(tput sgr0)
  Cb=$(tput setaf 4); Cc=$(tput setaf 6); Cy=$(tput setaf 3); Cr=$(tput setaf 1); Cg=$(tput setaf 2)
else B=""; D=""; R=""; Cb=""; Cc=""; Cy=""; Cr=""; Cg=""; fi
hr(){ printf "%s\n" "${D}$(printf "%0.s─" {1..150})${R}"; }
dbg(){ [ "$DEBUG" -eq 1 ] && echo "[DBG] $*" >&2 || true; }

# ---------- Args ----------
usage(){ cat <<EOF
${B}server-perf-test.sh${R} — Multi-node CPU spec & micro-bench (color table)
Uses your normal ssh config/keys. No pre-checks. No CSV. Minimal moving parts.

Usage:
  ./server-perf-test.sh [--install] [--parallel N] [--discover]

Options:
  --install       Try apt install sysbench and p7zip-full on Debian/Ubuntu nodes
  --parallel N    Run up to N nodes concurrently (default: serial)
  --discover      Append corosync ring0_addr hosts from /etc/pve/corosync.conf

Env:
  SSH_USER, SSH_PORT, SYSBENCH_TIME, OPENSSL_TIME, RUN_TIMEOUT, PARALLEL_JOBS, DEBUG
EOF
exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL_MISSING=1; shift ;;
    --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
    --discover) AUTO_DISCOVER=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# ---------- Optional discovery ----------
if [[ "$AUTO_DISCOVER" -eq 1 && -f /etc/pve/corosync.conf ]]; then
  mapfile -t DISC < <(awk '$1 ~ /ring0_addr:/ {sub(/ring0_addr:/,""); gsub(/[ \t,]+/,""); print}' /etc/pve/corosync.conf | sort -u)
  HOSTS+=("${DISC[@]}")
fi
# De-dupe and drop empties
readarray -t HOSTS < <(printf '%s\n' "${HOSTS[@]}" | awk 'NF' | awk '!seen[$0]++')
[ "${#HOSTS[@]}" -gt 0 ] || { echo "${Cr}ERROR${R}: no hosts"; exit 1; }

# ---------- Local detection ----------
is_local(){
  local h="$1"; local hs hf
  hs="$(hostname -s 2>/dev/null || true)"
  hf="$(hostname -f 2>/dev/null || true)"
  [[ "$h" == "127.0.0.1" || "$h" == "localhost" || "$h" == "$hs" || "$h" == "$hf" ]]
}

# ---------- Remote bench payload (one line out with pipes) ----------
remote_cmd_template() { cat <<'REMOTE'
set -euo pipefail
pkg() { command -v apt-get >/dev/null 2>&1 && echo apt || (command -v dnf >/dev-null 2>&1 && echo dnf || (command -v yum >/dev/null 2>&1 && echo yum || echo none)); }
OSPKG=$(pkg)
if [[ __INSTALL__ -eq 1 && "$OSPKG" == "apt" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  apt-get install -y -qq sysbench p7zip-full >/dev/null 2>&1 || true
fi

KERNEL=$(uname -r)
MODEL=$(lscpu 2>/dev/null | sed -n "s/^Model name:[[:space:]]*//p" | head -n1)
[[ -z "${MODEL:-}" ]] && MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed "s/^ //")
CORES=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,""); c=$2} /^Socket\(s\)/ {gsub(/ /,""); s=$2} END{if(c=="") c=1; if(s=="") s=1; print c*s}')
THREADS=$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/ {gsub(/ /,""); print $2; exit}')
CUR_MHZ=$(lscpu 2>/dev/null | sed -n "s/^CPU MHz:[[:space:]]*//p" | awk 'NR==1{print int($1)}')
MAX_MHZ=$(lscpu 2>/dev/null | sed -n "s/^CPU max MHz:[[:space:]]*//p" | awk 'NR==1{print int($1)}')
[[ -z "${CUR_MHZ:-}" ]] && CUR_MHZ=$(awk -F: "/cpu MHz/{print int(\$2); exit}" /proc/cpuinfo 2>/dev/null || echo "")

FLAGS=$(lscpu 2>/dev/null | sed -n "s/^Flags:[[:space:]]*//p")
has() { echo "$FLAGS" | grep -qw "$1" && echo yes || echo no; }
AES=$(has aes); AVX2=$(has avx2); AVX512=$(has avx512f)

SB_EPS="-"
if command -v sysbench >/dev/null 2>&1; then
  RAW=$(sysbench cpu --threads=$(nproc) --time __SBTIME__ run 2>/dev/null || true)
  SB_EPS=$(echo "$RAW" | awk -F: "/events per second/ {gsub(/ /,\"\"); print \$2; exit}")
  [[ -z "$SB_EPS" ]] && SB_EPS="-"
fi

OS_SHA="-"
if command -v openssl >/dev/null 2>&1; then
  SHA=$(openssl speed -elapsed -seconds __OSTIME__ sha256 2>/dev/null || true)
  OS_SHA=$(echo "$SHA" | awk '/sha256/ && /(8192 bytes|\(8192 bytes\))/ {print $NF}' | head -n1)
  [[ -z "$OS_SHA" ]] && OS_SHA="-"
fi

OS_AES="-"
if command -v openssl >/dev/null 2>&1; then
  AESO=$(OPENSSL_ia32cap=~0 openssl speed -elapsed -seconds __OSTIME__ -multi $(nproc) -evp aes-256-gcm 2>/dev/null || true)
  OS_AES=$(echo "$AESO" | awk '/aes-256-gcm/ && /evp/ {v=$NF} END{print v}')
  [[ -z "$OS_AES" ]] && OS_AES="-"
fi

SEVENZ="-"
if command -v 7z >/dev/null 2>&1; then
  B=$(7z b -mmt=$(nproc) -bso0 -bsp1 2>/dev/null || true)
  SEVENZ=$(echo "$B" | awk -F= "/^Total:/ {gsub(/ /,\"\"); print \$2; exit}")
  [[ -z "$SEVENZ" ]] && SEVENZ="-"
fi

echo "$KERNEL|$MODEL|$CORES|$THREADS|$CUR_MHZ|$MAX_MHZ|$AES|$AVX2|$AVX512|$SB_EPS|$OS_SHA|$OS_AES|$SEVENZ"
REMOTE
}
REMOTE_CMD="$(remote_cmd_template)"
REMOTE_CMD="${REMOTE_CMD//__INSTALL__/${INSTALL_MISSING}}"
REMOTE_CMD="${REMOTE_CMD//__SBTIME__/${SYSBENCH_TIME}}"
REMOTE_CMD="${REMOTE_CMD//__OSTIME__/${OPENSSL_TIME}}"

# ---------- SSH wrapper (honor your ~/.ssh/config) ----------
ssh_run(){
  local host="$1"; shift
  # Only option we force: ignore first-time hostkey prompt.
  ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "${SSH_USER}@${host}" "$@"
}

# ---------- Printing ----------
print_header(){
  hr
  printf "${B}${Cb}%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s${R}\n" \
    "host" "kernel" "model" "cores" "threads" "curMHz" "maxMHz" "AES" "AVX2" "AVX512" \
    "sysbench/s" "openssl-SHA256" "openssl-AES256GCM" "7z-MIPS"
  hr
}
print_row(){
  printf "%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
    "$1" "$2" "${3:0:27}" "${4:-?}" "${5:-?}" "${6:--}" "${7:--}" "${8:--}" "${9:--}" "${10:--}" "${11:--}" "${12:--}" "${13:--}" "${14:--}"
}

# ---------- Worker ----------
run_one(){
  local host="$1"
  echo "${D}[START]${R} $host"; dbg "ssh target: ${SSH_USER}@${host} port ${SSH_PORT}"
  local OUT=""
  if is_local "$host"; then
    if ! OUT=$(bash -lc "$REMOTE_CMD"); then
      print_row "$host" "local-failed" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
      echo "${D}[END  ]${R} $host (local-failed)"; return 0
    fi
  else
    if ! OUT=$(timeout "${RUN_TIMEOUT}s" ssh_run "$host" "$REMOTE_CMD" 2>/dev/null); then
      print_row "$host" "unreachable" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
      echo "${D}[END  ]${R} $host (unreachable)"; return 0
    fi
  fi
  IFS="|" read -r KERNEL MODEL CORES THREADS CUR_MHZ MAX_MHZ AES AVX2 AVX512 SB_EPS OS_SHA OS_AES SEVENZ <<< "$OUT"
  print_row "$host" "$KERNEL" "$MODEL" "$CORES" "$THREADS" "$CUR_MHZ" "$MAX_MHZ" "$AES" "$AVX2" "$AVX512" "$SB_EPS" "$OS_SHA" "$OS_AES" "$SEVENZ"
  echo "${D}[END  ]${R} $host"
}

export -f run_one print_row ssh_run is_local
export SSH_USER SSH_PORT RUN_TIMEOUT REMOTE_CMD

# ---------- Run ----------
echo "${Cc}Running on ${#HOSTS[@]} host(s)...${R}"
print_header
if [[ "$PARALLEL_JOBS" -gt 0 ]]; then
  printf "%s\n" "${HOSTS[@]}" | xargs -n1 -P "$PARALLEL_JOBS" -I{} bash -c 'run_one "$@"' _ {}
else
  for h in "${HOSTS[@]}"; do run_one "$h"; done
fi
hr
echo "${Cg}Done.${R}"
