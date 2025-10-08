#!/usr/bin/env bash
# server-inventory.sh

#
# run as bash server-inventory.sh
# This script collects an inventory of installed packages, services, system info,
# and configuration snapshots from a Debian-based Linux server.
# It saves the output in a timestamped directory under ~/server-inventory.  

#
# CHANGE LOG
# 2025-09-15 Initial version
# 2025-10-08 Rewritten (vibe code) with colorized output, preflight checks, and safe pause points.
# https://chatgpt.com/g/g-p-687d002409208191aad34157d6fc7ee4/c/68e693c1-9d34-832c-b213-89baae3f03b8 
#

set -Eeuo pipefail

############################
# Styling / UX (fixed for proper color init)
############################
# Initialize tput-based colors only if stdout is a terminal
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  bold=$(tput bold)
  dim=$(tput dim)
  reset=$(tput sgr0)
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  yellow=$(tput setaf 3)
  blue=$(tput setaf 4)
  magenta=$(tput setaf 5)
  cyan=$(tput setaf 6)
else
  bold=""; dim=""; reset=""
  red=""; green=""; yellow=""; blue=""; magenta=""; cyan=""
fi

# Shortcuts for messages
log()   { printf "%s[%s]%s %b%s%s\n" "$dim" "$(date '+%F %T')" "$reset" "$1" "$2" "$reset"; }
info()  { log "${cyan}${bold}INFO${reset} " "$*"; }
ok()    { log "${green}${bold} OK ${reset} " "$*"; }
warn()  { log "${yellow}${bold}WARN${reset} " "$*"; }
err()   { log "${red}${bold}ERR ${reset} " "$*"; }

trap 'echo; err "Interrupted. No changes beyond completed steps."; exit 130' INT

pause_point() {
  local msg="${1:-Press Enter to continue, or CTRL-C to abort…}"
  echo
  printf "%b%s%b\n" "${magenta}${bold}" "$msg" "$reset"
  read -r
}

############################
# Output locations
############################
ROOT_DIR="${HOME}/server-inventory"
RUN_ID="$(date +%F_%H%M%S)"
OUT_DIR="${ROOT_DIR}/${RUN_ID}"

LATEST_LINK="${ROOT_DIR}/latest"

############################
# What this script collects
############################
clear || true
printf "%b\n" "${bold}${cyan}=== Server Inventory: Plan of Action ===${reset}"

cat <<EOF
This run will collect and save the following into:
  ${bold}${OUT_DIR}${reset}

${blue}- APT / DPKG:${reset}
  • Full package selections (installed, hold, etc.)
  • Manually installed packages

${blue}- System Services & OS:${reset}
  • systemd services (enabled/disabled)
  • hostnamectl, lsb_release, uname details

${blue}- Language/Runtime Ecosystem (if present):${reset}
  • Python 'pip3 freeze'
  • NodeJS global packages (npm -g, depth 0)

${blue}- Containers (if present):${reset}
  • docker ps -a
  • docker images

${blue}- Config Snapshot:${reset}
  • Tarball of /etc -> ${bold}etc-backup-YYYY-MM-DD.tar.gz${reset}

${yellow}Notes:${reset}
  • Some steps are skipped gracefully if the tool is not installed.
  • /etc backup may need elevated read permissions; unreadable files skipped.
EOF

pause_point "Review the plan above. Press Enter to proceed, or CTRL-C to cancel…"

# (rest of your previous script remains unchanged)


############################
# Create directories
############################
info "Creating output directory at ${OUT_DIR}"
mkdir -p "${OUT_DIR}"
ok "Output directory ready"

# Helper to run a command if available
run_if_present() {
  local cmd="$1"; shift || true
  local outfile="$1"; shift || true
  if command -v "${cmd%% *}" >/dev/null 2>&1; then
    info "Running: ${cmd}"
    # shellcheck disable=SC2086
    if ${cmd} > "${OUT_DIR}/${outfile}" 2>&1; then
      ok "Saved -> ${outfile}"
    else
      warn "Command '${cmd}' completed with warnings. See ${outfile}"
    fi
  else
    warn "Skipping '${cmd}': not installed"
  fi
}

############################
# APT / DPKG
############################
run_if_present "dpkg --get-selections" "installed-packages.list"
run_if_present "apt-mark showmanual" "manual-packages.list"

############################
# Services
############################
run_if_present "systemctl list-unit-files --type=service" "services.list"

############################
# System Info
############################
SYSINFO="${OUT_DIR}/system-info.txt"
info "Collecting system info -> system-info.txt"
{
  if command -v hostnamectl >/dev/null 2>&1; then
    echo "# hostnamectl"; hostnamectl; echo
  else
    echo "# hostnamectl not available"
  fi

  if command -v lsb_release >/dev/null 2>&1; then
    echo "# lsb_release -a"; lsb_release -a; echo
  else
    echo "# lsb_release not available"
  fi

  echo "# uname -a"; uname -a; echo
} > "${SYSINFO}"
ok "Saved -> system-info.txt"

############################
# Python / Node Ecosystems
############################
run_if_present "pip3 freeze" "requirements.txt"
run_if_present "npm list -g --depth=0" "npm-global-packages.txt"

############################
# Docker (if installed)
############################
if command -v docker >/dev/null 2>&1; then
  info "Collecting Docker inventory"
  if docker ps -a > "${OUT_DIR}/docker-containers.txt" 2>&1; then
    ok "Saved -> docker-containers.txt"
  else
    warn "Could not list docker containers. See docker-containers.txt"
  fi

  if docker images > "${OUT_DIR}/docker-images.txt" 2>&1; then
    ok "Saved -> docker-images.txt"
  else
    warn "Could not list docker images. See docker-images.txt"
  fi
else
  warn "Docker not installed. Skipping container/image inventory."
fi

############################
# Pause point before /etc backup
############################
cat <<EOF

${bold}Next step: /etc configuration snapshot${reset}

We'll create a compressed archive of ${bold}/etc${reset}:
  -> ${OUT_DIR}/etc-backup-$(date +%F).tar.gz

This is read-only; files you lack permission to read will be skipped with warnings.

EOF

pause_point "Press Enter to create the /etc backup, or CTRL-C to skip/abort…"

############################
# /etc backup
############################
ETC_ARCHIVE="${OUT_DIR}/etc-backup-$(date +%F).tar.gz"
info "Creating /etc snapshot -> $(basename "${ETC_ARCHIVE}")"
# Use --warning=all so you can review any permission issues in the log
# Exclude some noisy/volatile paths if desired; keep minimal by default
if tar -czf "${ETC_ARCHIVE}" --warning=all /etc >/dev/null 2>&1; then
  ok "Saved -> $(basename "${ETC_ARCHIVE}")"
else
  warn "Tar completed with warnings or partial read. The archive may still be usable."
fi

############################
# Update 'latest' symlink
############################
if ln -sfn "${OUT_DIR}" "${LATEST_LINK}"; then
  ok "Updated 'latest' pointer -> ${LATEST_LINK}"
else
  warn "Could not update 'latest' symlink"
fi

############################
# Summary
############################
echo
printf "%b%s%b\n" "${green}${bold}" "Inventory complete." "${reset}"
echo
echo "Summary of outputs:"
echo "  ${bold}${OUT_DIR}/${reset}"
printf "    - %-30s %s\n" "installed-packages.list"   "DPKG selections"
printf "    - %-30s %s\n" "manual-packages.list"      "APT manual packages"
printf "    - %-30s %s\n" "services.list"             "systemd unit files"
printf "    - %-30s %s\n" "system-info.txt"           "hostnamectl / lsb_release / uname"
printf "    - %-30s %s\n" "requirements.txt"          "pip3 freeze (if present)"
printf "    - %-30s %s\n" "npm-global-packages.txt"   "npm -g depth=0 (if present)"
printf "    - %-30s %s\n" "docker-containers.txt"     "docker ps -a (if present)"
printf "    - %-30s %s\n" "docker-images.txt"         "docker images (if present)"
printf "    - %-30s %s\n" "$(basename "${ETC_ARCHIVE}")" "tar of /etc (warnings possible)"

echo
info "Tip: Use '${bold}ls -lah ${OUT_DIR}${reset}' to review files, or '${bold}ls -lah ${LATEST_LINK}${reset}' for the latest run."

# End of script
