#!/usr/bin/env bash
# homelab-motdctl — install/rollback a clean, colored MOTD on Proxmox/Debian
# Usage:
#   homelab-motdctl install [--about URL] [--disable-lastlog] [--keep-others]
#   homelab-motdctl rollback [TIMESTAMP]
#   homelab-motdctl status
#   homelab-motdctl preview
set -Eeuo pipefail

# ---------- Colors ----------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors)" -ge 8 ]] && [[ "${NO_COLOR:-0}" != "1" ]]; then
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"; BOLD="$(tput bold)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; DIM=""; RESET=""
fi
info ()  { echo -e "${BLUE}[*]${RESET} $*"; }
ok   ()  { echo -e "${GREEN}[✔]${RESET} $*"; }
warn ()  { echo -e "${YELLOW}[!]${RESET} $*"; }
err  ()  { echo -e "${RED}[✖]${RESET} $*" >&2; }
step ()  { echo -e "\n${BOLD}${MAGENTA}==>${RESET} $*"; }
trap 'err "Error on line ${BASH_LINENO[0]}"; exit 1' ERR

# ---------- Paths / constants ----------
MOTD_DIR="/etc/update-motd.d"
MOTD_FILE="${MOTD_DIR}/10-homelab"
BACKUP_DIR="/var/backups/homelab-motd"
LASTLOG_CONF="/etc/ssh/sshd_config.d/99-no-lastlog-homelab.conf"

require_root () {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -- "$0" "$@"
    else
      err "Run as root (or install sudo)."
      exit 1
    fi
  fi
}

need_pkg () {
  dpkg -s "$1" >/dev/null 2>&1 || { step "Install $1"; apt-get update -y && apt-get install -y "$1"; ok "$1 installed"; }
}

backup_now () {
  mkdir -p "$BACKUP_DIR"
  local ts; ts="$(date +%Y%m%d%H%M%S)"
  step "Backup current MOTD state -> ${BACKUP_DIR} (timestamp ${ts})"
  if [[ -d "$MOTD_DIR" ]]; then
    tar -C /etc -cpzf "${BACKUP_DIR}/update-motd.d-${ts}.tgz" "update-motd.d"
  else
    warn "No ${MOTD_DIR} directory to back up (will create fresh)"
  fi
  if [[ -f /etc/motd ]]; then
    cp -a /etc/motd "${BACKUP_DIR}/motd-${ts}"
  fi
  echo "$ts" > "${BACKUP_DIR}/last_install"
  ok "Backup saved: ${ts}"
  echo "$ts"
}


restore_backup () {
  local ts="$1"
  [[ -z "${ts}" ]] && err "No timestamp provided to rollback" && exit 1
  local tarball="${BACKUP_DIR}/update-motd.d-${ts}.tgz"
  local motdfile="${BACKUP_DIR}/motd-${ts}"
  step "Rollback to backup ${ts}"
  if [[ -f "$tarball" ]]; then
    rm -rf "$MOTD_DIR"
    tar -C /etc -xpzf "$tarball"
    ok "Restored ${MOTD_DIR}"
  else
    warn "No tarball for ${ts}; leaving ${MOTD_DIR} as-is"
  fi
  if [[ -f "$motdfile" ]]; then
    cp -a "$motdfile" /etc/motd
    ok "Restored /etc/motd"
  else
    warn "No saved /etc/motd for ${ts}; leaving current file"
  fi
  if [[ -f "$LASTLOG_CONF" ]] && grep -q "homelab-motd" "$LASTLOG_CONF"; then
    rm -f "$LASTLOG_CONF"
    systemctl reload ssh || true
    ok "Removed homelab last-login override and reloaded ssh"
  fi
  ok "Rollback complete."
}

write_template () {
  # Writes ${MOTD_FILE} with placeholder __ABOUT_URL__ to be replaced after
  install -d "$MOTD_DIR"
  cat > "$MOTD_FILE" <<'EOF'
#!/bin/sh
# 10-homelab — colored MOTD (managed by homelab-motdctl)
# ABOUT_URL is set by the installer; leave blank to hide link.
ABOUT_URL="__ABOUT_URL__"

ESC="$(printf '\033')"
cyan="${ESC}[1;36m"; green="${ESC}[1;32m"; yellow="${ESC}[1;33m"; mag="${ESC}[1;35m"; blue="${ESC}[1;34m"
dim="${ESC}[2m"; bold="${ESC}[1m"; reset="${ESC}[0m"

DATE="$(date '+%a %b %d %I:%M:%S %p %Z %Y')"
LOAD="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"

DISK_LINE="$(df -h -x tmpfs -x devtmpfs -x squashfs --output=pcent,size,target / | tail -n1)"
DISK_PCT="$(printf "%s" "$DISK_LINE" | awk '{print $1}')"
DISK_SIZE="$(printf "%s" "$DISK_LINE" | awk '{print $2}')"
DISK_STR="${DISK_PCT:-n/a} of ${DISK_SIZE:-n/a}"

MEM_TOTAL_MB="$(awk '/MemTotal/ {printf("%d",$2/1024)}' /proc/meminfo)"
MEM_AVAIL_MB="$(awk '/MemAvailable/ {printf("%d",$2/1024)}' /proc/meminfo)"
if [ -n "$MEM_TOTAL_MB" ] && [ -n "$MEM_AVAIL_MB" ] && [ "$MEM_TOTAL_MB" -gt 0 ]; then
  MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))
  MEM_PCT=$(( 100 * MEM_USED_MB / MEM_TOTAL_MB ))
  MEM_STR="${MEM_PCT}% of ${MEM_TOTAL_MB}MB"
else
  MEM_STR="n/a"
fi

SWAP_TOTAL_MB="$(awk '/SwapTotal/ {printf("%d",$2/1024)}' /proc/meminfo)"
SWAP_FREE_MB="$(awk '/SwapFree/  {printf("%d",$2/1024)}' /proc/meminfo)"
if [ -n "$SWAP_TOTAL_MB" ] && [ "$SWAP_TOTAL_MB" -gt 0 ]; then
  SWAP_USED_MB=$((SWAP_TOTAL_MB - SWAP_FREE_MB))
  SWAP_PCT=$(( 100 * SWAP_USED_MB / SWAP_TOTAL_MB ))
  SWAP_STR="${SWAP_PCT}% of ${SWAP_TOTAL_MB}MB"
else
  SWAP_STR="disabled"
fi

PROCS="$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')"
USERS="$(who 2>/dev/null | wc -l | tr -d ' ')"

IPV4="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | paste -sd ' ' -)"
IPV6="$(ip -o -6 addr show scope global 2>/dev/null | awk '{print $4}' | paste -sd ' ' -)"
[ -z "$IPV4" ] && IPV4="n/a"
[ -z "$IPV6" ] && IPV6="n/a"

HOST="$(hostname)"
HOST_UP="$(printf "%s" "$HOST" | tr '[:lower:]' '[:upper:]')"
KERNEL="$(uname -r)"
PVE="$(command -v pveversion >/dev/null 2>&1 && pveversion | head -n1)"

line() { printf '%*s\n' 59 '' | tr ' ' '='; }

printf "%s%s%s\n" "$cyan" "$(line)" "$reset"
printf "%s%-16s%s %s\n" "$green" "System Date:" "$reset" "$DATE"
printf "%s%-16s%s %s\n" "$green" "Load Average:" "$reset" "${LOAD:-n/a}"
printf "%s%-16s%s %s\n" "$green" "Disk Usage:"   "$reset" "$DISK_STR"
printf "%s%-16s%s %s\n" "$green" "Memory Usage:" "$reset" "$MEM_STR"
printf "%s%-16s%s %s\n" "$green" "Swap Usage:"   "$reset" "$SWAP_STR"
printf "%s%-16s%s %s\n" "$green" "Processes:"    "$reset" "${PROCS:-n/a}"
printf "%s%-16s%s %s\n" "$green" "Users Logged:" "$reset" "${USERS:-n/a}"
printf "%s%-16s%s %s\n" "$green" "IPv4 Address:" "$reset" "$IPV4"
printf "%s%-16s%s %s\n" "$green" "IPv6 Address:" "$reset" "$IPV6"
[ -n "$PVE" ] && printf "%s%-16s%s %s\n" "$green" "Proxmox:" "$reset" "$PVE"
printf "%s%s%s\n" "$cyan" "$(line)" "$reset"
printf "%s   💻  HOSTNAME:%s %s\n" "$mag" "$reset" "$HOST_UP"
printf "%s%s%s\n" "$cyan" "$(line)" "$reset"

if [ -n "$ABOUT_URL" ]; then
  printf "%s%s%s\n" "$blue" "$(line)" "$reset"
  printf "%sAbout This Box:%s %s\n" "$bold" "$reset" "$ABOUT_URL"
  printf "%s%s%s\n" "$blue" "$(line)" "$reset"
else
  printf "%s%s%s\n" "$cyan" "$(line)" "$reset"
fi
EOF
  chmod 0755 "$MOTD_FILE"
}

disable_others () {
  shopt -s nullglob
  for f in "${MOTD_DIR}"/*; do
    [[ "$f" == "$MOTD_FILE" ]] && continue
    chmod -x "$f" 2>/dev/null || true
  done
}

enable_all () {
  shopt -s nullglob
  for f in "${MOTD_DIR}"/*; do chmod +x "$f" 2>/dev/null || true; done
}

install_action () {
  require_root "$@"
  need_pkg tar
  install_about=""
  disable_lastlog=0
  keep_others=0

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --about) shift; install_about="${1:-}";;
      --disable-lastlog) disable_lastlog=1;;
      --keep-others) keep_others=1;;
      *) break;;
    esac
    shift || true
  done

  local ts; ts="$(backup_now)"

  step "Install new MOTD"
  write_template
  # Inject ABOUT_URL into template
  sed -i "s|__ABOUT_URL__|${install_about}|g" "$MOTD_FILE"
  ok "Installed ${MOTD_FILE}"

  if [[ "$keep_others" -eq 0 ]]; then
    step "Disable other MOTD scripts"
    disable_others
    ok "Only 10-homelab will run"
  else
    warn "Keeping other MOTD scripts enabled (--keep-others)"
  fi

  step "Clear static /etc/motd blurb"
  : > /etc/motd
  ok "/etc/motd cleared"

  if [[ "$disable_lastlog" -eq 1 ]]; then
    step "Disable SSH 'Last login' line"
    cat > "$LASTLOG_CONF" <<EOF
# managed by homelab-motdctl (homelab-motd)
PrintLastLog no
EOF
    systemctl reload ssh || true
    ok "SSH reloaded; last login suppressed"
  fi

  step "Preview"
  run-parts "$MOTD_DIR" || true

  ok "Install finished. Backup timestamp: ${ts}"
}

rollback_action () {
  require_root
  local ts="${1:-}"
  if [[ -z "$ts" && -f "${BACKUP_DIR}/last_install" ]]; then
    ts="$(<"${BACKUP_DIR}/last_install")"
  fi
  if [[ -z "$ts" ]]; then
    err "No backup timestamp found. Provide one: rollback YYYYmmddHHMMSS"
    exit 1
  fi
  restore_backup "$ts"
  step "Preview after rollback"
  run-parts "$MOTD_DIR" || true
}

status_action () {
  echo -e "${DIM}MOTD dir   :${RESET} ${MOTD_DIR}"
  echo -e "${DIM}MOTD file  :${RESET} ${MOTD_FILE} $( [[ -x "$MOTD_FILE" ]] && echo "${GREEN}[enabled]${RESET}" || echo "${YELLOW}[missing/disabled]${RESET}" )"
  if [[ -f "${BACKUP_DIR}/last_install" ]]; then
    echo -e "${DIM}Last backup:${RESET} $(<"${BACKUP_DIR}/last_install")"
  else
    echo -e "${DIM}Last backup:${RESET} none"
  fi
  if [[ -f "$LASTLOG_CONF" ]]; then
    echo -e "${DIM}Last-login :${RESET} disabled (homelab)"
  else
    echo -e "${DIM}Last-login :${RESET} default"
  fi
  echo -e "${DIM}Other scripts:${RESET}"
  ls -l "$MOTD_DIR" 2>/dev/null || echo "  (no directory)"
}

preview_action () {
  run-parts "$MOTD_DIR"
}

usage () {
  cat <<USAGE
${BOLD}homelab-motdctl${RESET}
  install [--about URL] [--disable-lastlog] [--keep-others]
  rollback [TIMESTAMP]
  status
  preview
USAGE
}

# ---------- Main dispatch ----------
cmd="${1:-}"; shift || true
case "$cmd" in
  install)  install_action "$@" ;;
  rollback) rollback_action "$@" ;;
  status)   status_action ;;
  preview)  preview_action ;;
  ""|help|-h|--help) usage ;;
  *) err "Unknown command: $cmd"; usage; exit 1;;
esac
