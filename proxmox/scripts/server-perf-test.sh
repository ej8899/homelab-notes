#!/usr/bin/env bash
# server-perf-test.sh — Multi-node CPU spec & micro-bench (colorized, no CSV, sshpass)
# Runs: sysbench cpu, openssl speed (sha256 + aes-256-gcm), optional 7z MIPS
# Auth: passworded SSH via sshpass (no keys). Provide password as env or prompt.
# ------------------------------------------------------------------------------

set -euo pipefail

# ========================= USER CONFIG =========================
# 1) Built-in hosts list (IPs or resolvable names). Edit to your environment.
HOSTS_BUILTIN=(
  "lab"             
  "hypnoserver"    
  "nimbus"          
  "vginy"           
  "NibblersNothings"

)

# 2) Auto-discover from /etc/pve/corosync.conf ring0_addr (1=enabled, 0=disabled)
AUTO_DISCOVER="${AUTO_DISCOVER:-1}"

# 3) Defaults (overridable via env)
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_PASSWORD="${SSH_PASSWORD:-}"      # if empty, script will prompt once (hidden)
SYSBENCH_TIME="${SYSBENCH_TIME:-20}"  # seconds per node for sysbench
OPENSSL_TIME="${OPENSSL_TIME:-10}"    # seconds per openssl test
PARALLEL_JOBS="${PARALLEL_JOBS:-0}"   # 0=serial; else parallelism for nodes
REACH_TIMEOUT="${REACH_TIMEOUT:-8}"   # seconds for "quick reachability" check
RUN_TIMEOUT="${RUN_TIMEOUT:-120}"     # seconds for full remote command
# ===============================================================

# --------------------------- UI COLORS -------------------------
use_color=1
if ! [ -t 1 ]; then use_color=0; fi
if [ "${NO_COLOR:-}" = "1" ]; then use_color=0; fi

if [ "$use_color" -eq 1 ] && command -v tput >/dev/null 2>&1; then
  bold=$(tput bold); dim=$(tput dim); reset=$(tput sgr0)
  fg_green=$(tput setaf 2); fg_yellow=$(tput setaf 3); fg_red=$(tput setaf 1); fg_cyan=$(tput setaf 6); fg_blue=$(tput setaf 4)
else
  bold=""; dim=""; reset=""; fg_green=""; fg_yellow=""; fg_red=""; fg_cyan=""; fg_blue=""
fi

info()   { echo "${fg_cyan}${1}${reset}"; }
warn()   { echo "${fg_yellow}WARN:${reset} ${1}"; }
error()  { echo "${fg_red}ERROR:${reset} ${1}"; }
ok()     { echo "${fg_green}${1}${reset}"; }

# --------------------------- USAGE -----------------------------
usage() {
  cat <<EOF
${bold}server-perf-test.sh${reset}
Multi-node CPU spec & micro-benchmark (color table, sshpass; no CSV)

${bold}Usage:${reset}
  ./server-perf-test.sh [--install] [--parallel N] [--no-discover]

${bold}Auth:${reset}
  - Install sshpass: ${dim}apt-get install -y sshpass${reset}
  - Provide the password via env or prompt:
      SSH_USER=root SSH_PASSWORD='yourpass' ./server-perf-test.sh --parallel 3
    (If SSH_PASSWORD is empty, you'll be prompted once — hidden input.)

${bold}Options:${reset}
  --install         Attempt apt install of sysbench and p7zip-full on each node
  --parallel N      Run up to N nodes in parallel
  --no-discover     Disable corosync auto-discovery; use HOSTS_BUILTIN only

${bold}Env overrides:${reset}
  SSH_USER, SSH_PORT, SSH_PASSWORD, SYSBENCH_TIME, OPENSSL_TIME, PARALLEL_JOBS,
  REACH_TIMEOUT, RUN_TIMEOUT, AUTO_DISCOVER
EOF
  exit 1
}

# ------------------------- ARG PARSING -------------------------
INSTALL_MISSING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL_MISSING=1; shift ;;
    --parallel) PARALLEL_JOBS="$2"; shift 2 ;;
    --no-discover) AUTO_DISCOVER=0; shift ;;
    -h|--help) usage ;;
    *) error "Unknown arg: $1"; usage ;;
  esac
done

# ------------------------ SSH WRAPPERS -------------------------
SSH_BASE_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=${REACH_TIMEOUT} -p ${SSH_PORT}"

need_sshpass() {
  if [[ -z "${SSH_PASSWORD}" ]]; then
    # Ask once
    read -r -s -p "SSH password for ${SSH_USER}: " SSH_PASSWORD
    echo
  fi
  if ! command -v sshpass >/dev/null 2>&1; then
    error "sshpass not installed. Run: apt-get install -y sshpass"
    exit 1
  fi
}

ssh_exec() {
  local host="$1"; shift
  sshpass -p "$SSH_PASSWORD" ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    $SSH_BASE_OPTS "${SSH_USER}@${host}" "$@"
}

# ---------------------- HOST DISCOVERY -------------------------
HOSTS=()

if [[ "$AUTO_DISCOVER" -eq 1 && -f /etc/pve/corosync.conf ]]; then
  mapfile -t HOSTS < <(awk '
    $1 ~ /ring0_addr:/ {
      sub(/ring0_addr:/,""); gsub(/[ \t,]+/,""); print
    }' /etc/pve/corosync.conf | sort -u)
fi

# If nothing found via corosync OR discovery disabled, use built-in list
if [[ ${#HOSTS[@]} -eq 0 ]]; then
  HOSTS=("${HOSTS_BUILTIN[@]}")
fi

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  error "No hosts found (corosync disabled/empty and HOSTS_BUILTIN is empty)."
  exit 1
fi

# --------------------- REMOTE BENCH SCRIPT ---------------------
# Emits a single pipe-delimited line:
# KERNEL|MODEL|CORES|THREADS|CUR_MHZ|MAX_MHZ|AES|AVX2|AVX512|SB_EPS|OS_SHA|OS_AES|SEVENZ
remote_cmd_template() {
cat <<'REMOTE'
set -euo pipefail

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
  if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1; then echo yum; return; fi
  echo none
}
OSPKG=$(detect_pkg)

if [[ __INSTALL_MISSING__ -eq 1 && "$OSPKG" == "apt" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  apt-get install -y -qq sysbench p7zip-full >/dev/null 2>&1 || true
fi

KERNEL=$(uname -r)
MODEL=$(lscpu 2>/dev/null | sed -n "s/^Model name:[[:space:]]*//p" | head -n1)
if [[ -z "${MODEL:-}" ]]; then
  MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed "s/^ //")
fi

CORES=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,""); c=$2}
                                      /^Socket\(s\)/ {gsub(/ /,""); s=$2}
                                      END{if(c=="") c=1; if(s=="") s=1; print c*s}')
THREADS=$(lscpu 2>/dev/null | awk -F: '/^CPU\(s\)/ {gsub(/ /,""); print $2; exit}')
CUR_MHZ=$(lscpu 2>/dev/null | sed -n "s/^CPU MHz:[[:space:]]*//p" | awk 'NR==1{print int($1)}')
MAX_MHZ=$(lscpu 2>/dev/null | sed -n "s/^CPU max MHz:[[:space:]]*//p" | awk 'NR==1{print int($1)}')
if [[ -z "${CUR_MHZ:-}" ]]; then CUR_MHZ=$(awk -F: "/cpu MHz/{print int(\$2); exit}" /proc/cpuinfo 2>/dev/null || echo ""); fi

FLAGS=$(lscpu 2>/dev/null | sed -n "s/^Flags:[[:space:]]*//p")
has() { echo "$FLAGS" | grep -qw "$1" && echo yes || echo no; }
AES=$(has aes); AVX2=$(has avx2); AVX512=$(has avx512f)

SB_EPS="-"
if command -v sysbench >/dev/null 2>&1; then
  RAW=$(sysbench cpu --threads=$(nproc) --time __SYSBENCH_TIME__ run 2>/dev/null || true)
  SB_EPS=$(echo "$RAW" | awk -F: "/events per second/ {gsub(/ /,\"\"); print \$2; exit}")
  [[ -z "$SB_EPS" ]] && SB_EPS="-"
fi

OS_SHA="-"
if command -v openssl >/dev/null 2>&1; then
  SHA=$(openssl speed -elapsed -seconds __OPENSSL_TIME__ sha256 2>/dev/null || true)
  OS_SHA=$(echo "$SHA" | awk '/sha256/ && /(8192 bytes|\(8192 bytes\))/ {print $NF}' | head -n1)
  [[ -z "$OS_SHA" ]] && OS_SHA="-"
fi

OS_AES="-"
if command -v openssl >/dev/null 2>&1; then
  AESO=$(OPENSSL_ia32cap=~0 openssl speed -elapsed -seconds __OPENSSL_TIME__ -multi $(nproc) -evp aes-256-gcm 2>/dev/null || true)
  OS_AES=$(echo "$AESO" | awk '/aes-256-gcm/ && /evp/ {v=$NF} END{print v}')
  [[ -z "$OS_AES" ]] && OS_AES="-"
fi

SEVENZ="-"
if command -v 7z >/dev/null 2>&1; then
  B=$(7z b -mmt=$(nproc) -bso0 -bsp1 2>/dev/null || true)
  SEVENZ=$(echo "$B" | awk -F= "/^Total:/ {gsub(/ /,\"\"); print \$2; exit}")
  [[ -z "$SEVENZ" ]] && SEVENZ="-"
fi

echo "$KERNEL|${MODEL}|${CORES}|${THREADS}|${CUR_MHZ}|${MAX_MHZ}|${AES}|${AVX2}|${AVX512}|${SB_EPS}|${OS_SHA}|${OS_AES}|${SEVENZ}"
REMOTE
}

# bake values into the remote script
REMOTE_CMD="$(remote_cmd_template)"
REMOTE_CMD="${REMOTE_CMD//__INSTALL_MISSING__/${INSTALL_MISSING}}"
REMOTE_CMD="${REMOTE_CMD//__SYSBENCH_TIME__/${SYSBENCH_TIME}}"
REMOTE_CMD="${REMOTE_CMD//__OPENSSL_TIME__/${OPENSSL_TIME}}"

# ------------------------- TABLE HEADER ------------------------
print_header() {
  printf "%s\n" "${dim}$(printf "%0.s─" {1..150})${reset}"
  printf "${bold}${fg_blue}%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s${reset}\n" \
    "host" "kernel" "model" "cores" "threads" "curMHz" "maxMHz" "AES" "AVX2" "AVX512" \
    "sysbench/s" "openssl-SHA256" "openssl-AES256GCM" "7z-MIPS"
  printf "%s\n" "${dim}$(printf "%0.s─" {1..150})${reset}"
}

print_row() {
  # Args in order:
  # host KERNEL MODEL CORES THREADS CUR_MHZ MAX_MHZ AES AVX2 AVX512 SB_EPS OS_SHA OS_AES SEVENZ
  local host="$1"; shift
  printf "%-12s %-18s %-28s %-5s %-7s %-7s %-7s %-4s %-5s %-7s %-12s %-15s %-18s %-8s\n" \
    "$host" "${1}" "${2:0:27}" "${3:-?}" "${4:-?}" "${5:--}" "${6:--}" \
    "${7:--}" "${8:--}" "${9:--}" "${10:--}" "${11:--}" "${12:--}" "${13:--}"
}

# --------------------------- WORKER ----------------------------
run_one() {
  local host="$1"
  echo "${dim}[START]${reset} ${host}"
  # quick reachability
  if ! timeout "${REACH_TIMEOUT}s" ssh_exec "$host" "echo ok" >/dev/null 2>&1; then
    warn "cannot reach ${host}"
    print_row "$host" "unreachable" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
    echo "${dim}[END  ]${reset} ${host} (unreachable)"
    return 0
  fi

  # run remote script
  local OUT
  if ! OUT=$(timeout "${RUN_TIMEOUT}s" ssh_exec "$host" "$REMOTE_CMD"); then
    warn "benchmark timed out on ${host}"
    print_row "$host" "timeout" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-" "-"
    echo "${dim}[END  ]${reset} ${host} (timeout)"
    return 0
  fi

  IFS="|" read -r KERNEL MODEL CORES THREADS CUR_MHZ MAX_MHZ AES AVX2 AVX512 SB_EPS OS_SHA OS_AES SEVENZ <<< "$OUT"
  print_row "$host" "$KERNEL" "$MODEL" "$CORES" "$THREADS" "$CUR_MHZ" "$MAX_MHZ" "$AES" "$AVX2" "$AVX512" "$SB_EPS" "$OS_SHA" "$OS_AES" "$SEVENZ"
  echo "${dim}[END  ]${reset} ${host}"
}

export -f run_one print_row ssh_exec
export SSH_PASSWORD SSH_USER SSH_PORT SSH_BASE_OPTS REACH_TIMEOUT RUN_TIMEOUT REMOTE_CMD

# --------------------------- RUN -------------------------------
need_sshpass

info "Running on ${#HOSTS[@]} host(s)..."
print_header

if [[ "${PARALLEL_JOBS}" -gt 0 ]]; then
  # GNU xargs parallelism
  printf "%s\n" "${HOSTS[@]}" | xargs -n1 -P "${PARALLEL_JOBS}" -I{} bash -c 'run_one "$@"' _ {}
else
  for h in "${HOSTS[@]}"; do run_one "$h"; done
fi

printf "%s\n" "${dim}$(printf "%0.s─" {1..150})${reset}"
ok "Done."
