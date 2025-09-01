#!/usr/bin/env bash
# server-perf-test.sh — Multi-node CPU spec & micro-bench
# Auth: tries PUBLIC KEY first; if that fails AND SSH_PASSWORD is set, uses sshpass.
# Output: colorized terminal table (no CSV)

set -euo pipefail

# ========================= USER CONFIG =========================
HOSTS_BUILTIN=(
  "lab"             # replace/keep as you like
  "hypnoserver"
  "nimbus"
  "vginy"
  "NibblersNothings"
  # "192.168.1.10"
  # "192.168.1.11"
)
AUTO_DISCOVER="${AUTO_DISCOVER:-1}"  # 1=use corosync ring0_addr if available
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_PASSWORD="${SSH_PASSWORD:-}"      # optional; if set, used as fallback
SYSBENCH_TIME="${SYSBENCH_TIME:-20}"
OPENSSL_TIME="${OPENSSL_TIME:-10}"
PARALLEL_JOBS="${PARALLEL_JOBS:-0}"   # 0=serial
REACH_TIMEOUT="${REACH_TIMEOUT:-8}"
RUN_TIMEOUT="${RUN_TIMEOUT:-120}"
# ===============================================================

# --------------------------- COLORS ----------------------------
use_color=1; [ -t 1 ] || use_color=0; [ "${NO_COLOR:-}" = "1" ] && use_color=0
if [ "$use_color" -eq 1 ] && command -v tput >/dev/null 2>&1; then
  bold=$(tput bold); dim=$(tput dim); reset=$(tput sgr0)
  blue=$(tput setaf 4); cyan=$(tput setaf 6); yellow=$(tput setaf 3); red=$(tput setaf 1); green=$(tput setaf 2)
else bold=""; dim=""; reset=""; blue=""; cyan=""; yellow=""; red=""; green=""; fi
hr() { printf "%s\n" "${dim}$(printf "%0.s─" {1..150})${reset}"; }

# ---------------------------- UI -------------------------------
usage() {
  cat <<EOF
${bold}server-perf-test.sh${reset} — Multi-node CPU spec & micro-bench (color table)
Auth order: ${bold}public-key${reset} → ${bold}sshpass${reset} (if SSH_PASSWORD set)

Usage:
  ./server-perf-test.sh [--install] [--parallel N] [--no-discover]

Options:
  --install       apt install sysbench, p7zip-full on nodes (if apt present)
  --parallel N    run up to N nodes concurrently
  --no-discover   skip corosync discovery; use HOSTS_BUILTIN only

Env:
  SSH_USER, SSH_PORT, SSH_PASSWORD, SYSBENCH_TIME, OPENSSL_TIME, PARALLEL_JOBS, REACH_TIMEOUT, RUN_TIMEOUT, AUTO_DISCOVER
EOF
  exit 1
}

INSTALL_MISSING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL_MISSING=1; shift ;;
    --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
    --no-discover) AUTO_DISCOVER=0; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# ------------------------- HOSTS -------------------------------
HOSTS=()
if [[ "$AUTO_DISCOVER" -eq 1 && -f /etc/pve/corosync.conf ]]; then
  mapfile -t HOSTS < <(awk '$1 ~ /ring0_addr:/ {sub(/ring0_addr:/,""); gsub(/[ \t,]+/,""); print}' /etc/pve/corosync.conf | sort -u)
fi
[[ ${#HOSTS[@]} -eq 0 ]] && HOSTS=("${HOSTS_BUILTIN[@]}")
[[ ${#HOSTS[@]} -eq 0 ]] && { echo "${red}ERROR:${reset} no hosts"; exit 1; }

# --------------------- AUTH HELPERS ----------------------------
SSH_BASE="-o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o ConnectTimeout=${REACH_TIMEOUT} -p ${SSH_PORT}"
ssh_pubkey() {  # BatchMode=yes: fail fast if no key works; no password prompts
  ssh -o BatchMode=yes $SSH_BASE "${SSH_USER}@${1}" "${2}"
}
ssh_pass() {    # only used if SSH_PASSWORD provided
  command -v sshpass >/dev/null 2>&1 || { echo "${red}ERROR:${reset} sshpass not installed (apt-get install -y sshpass)"; return 127; }
  SSH_ASKPASS_REQUIRE=never sshpass -p "$SSH_PASSWORD" ssh \
    -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no \
    $SSH_BASE "${SSH_USER}@${1}" "${2}"
}

can_pubkey() { timeout "${REACH_TIMEOUT}s" ssh_pubkey "$1" "echo ok" >/dev/null 2>&1; }
can_pass()   { [[ -n "${SSH_PASSWORD}" ]] && timeout "${REACH_TIMEOUT}s" ssh_pass "$1" "echo ok" >/dev/null 2>&1; }

# --------------------- LOCAL DETECTION -------------------------
is_local() {
  local h="$1"; local hs; hs="$(hostname -s)"
  [[ "$h" == "127.0.0.1" || "$h" == "localhost" || "$h" == "$hs" || "$h" == "$(hostname -f)" ]]
}

# ------------------ REMOTE BENCH SCRIPT -----------------------
remote_cmd_template() { cat <<'REMOTE'
set -euo pipefail
pkg() { command -v apt-get >/dev/null 2>&1 && echo apt || (command -v dnf >/dev/null 2>&1 && echo dnf || (command -v yum >/dev/null 2>&1 && echo yum || echo none)); }
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

# --------------------- TABLE PRINTING --------------------------
print_header() {
  hr
  printf "${bold}${blue}%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s${reset}\n" \
    "host" "kernel" "model" "cores" "threads" "curMHz" "maxMHz" "AES" "AVX2" "AVX512" \
    "sysbench/s" "openssl-SHA256" "openssl-AES256GCM" "7z-MIPS"
  hr
}
print_row() {
  printf "%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
    "$1" "${2}" "${3:0:27}" "${4:-?}" "${5:-?}" "${6:--}" "${7:--}" "${8:--}" "${9:--}" "${10:--}" "${11:--}" "${12:--}" "${13:--}" "${14:--}"
}

# --------------------------- WORKER ----------------------------
run_one() {
  local host="$1"
  echo "${dim}[START]${reset} ${host}"

  local OUT
  if is_local "$host"; then
    # run locally (no ssh)
    if ! OUT=$(bash -lc "$REMOTE_CMD"); then
      print_row "$host" "local-failed" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
      echo "${dim}[END  ]${reset} ${host} (local-failed)"; return 0
    fi
  else
    if can_pubkey "$host"; then
      if ! OUT=$(timeout "${RUN_TIMEOUT}s" ssh_pubkey "$host" "$REMOTE_CMD"); then
        print_row "$host" "timeout" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
        echo "${dim}[END  ]${reset} ${host} (timeout)"; return 0
      fi
    elif can_pass "$host"; then
      if ! OUT=$(timeout "${RUN_TIMEOUT}s" ssh_pass "$host" "$REMOTE_CMD"); then
        print_row "$host" "timeout" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
        echo "${dim}[END  ]${reset} ${host} (timeout)"; return 0
      fi
    else
      echo "${yellow}WARN:${reset} cannot reach ${host} (no pubkey access; no/failed password fallback)"
      print_row "$host" "unreachable" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
      echo "${dim}[END  ]${reset} ${host} (unreachable)"; return 0
    fi
  fi

  IFS="|" read -r KERNEL MODEL CORES THREADS CUR_MHZ MAX_MHZ AES AVX2 AVX512 SB_EPS OS_SHA OS_AES SEVENZ <<< "$OUT"
  print_row "$host" "$KERNEL" "$MODEL" "$CORES" "$THREADS" "$CUR_MHZ" "$MAX_MHZ" "$AES" "$AVX2" "$AVX512" "$SB_EPS" "$OS_SHA" "$OS_AES" "$SEVENZ"
  echo "${dim}[END  ]${reset} ${host}"
}

export -f run_one print_row ssh_pubkey ssh_pass can_pubkey can_pass is_local
export SSH_USER SSH_PORT SSH_PASSWORD SSH_BASE REACH_TIMEOUT RUN_TIMEOUT REMOTE_CMD

# ---------------------------- RUN ------------------------------
echo "${cyan}Running on ${#HOSTS[@]} host(s)...${reset}"
print_header
if [[ "${PARALLEL_JOBS}" -gt 0 ]]; then
  printf "%s\n" "${HOSTS[@]}" | xargs -n1 -P "${PARALLEL_JOBS}" -I{} bash -c 'run_one "$@"' _ {}
else
  for h in "${HOSTS[@]}"; do run_one "$h"; done
fi
hr
echo "${green}Done.${reset}"
