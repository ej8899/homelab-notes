#!/usr/bin/env bash
# nut-setup.sh — Minimal, step-by-step UPS (USB) setup for Proxmox/Debian
# - Detects USB UPS (auto-continues if found)
# - Installs minimal NUT packages (only if missing, with confirmation)
# - Creates minimal configs (with backup-once)
# - Starts driver & server
# - Prints PeaNUT-ready details


set -euo pipefail

############ Colors & helpers ############
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RED="$(tput setaf 1)"; GRN="$(tput setaf 2)"; YEL="$(tput setaf 3)"
  BLU="$(tput setaf 4)"; CYA="$(tput setaf 6)"; DIM="$(tput dim)"; RST="$(tput sgr0)"
else
  BOLD=""; RED=""; GRN=""; YEL=""; BLU=""; CYA=""; DIM=""; RST=""
fi
step() { echo -e "${BOLD}${BLU}▶ $*${RST}"; }
ok()   { echo -e "${GRN}✓${RST} $*"; }
warn() { echo -e "${YEL}!${RST} $*"; }
err()  { echo -e "${RED}✗${RST} $*"; }
info() { echo -e "${CYA}i${RST} $*"; }

trap 'echo; warn "Exited by user (CTRL-C). Nothing changed."; exit 1' INT

############ Root check ############
if [[ $EUID -ne 0 ]]; then err "Run as root (sudo)."; exit 1; fi

echo -e "${BOLD}NUT Minimal UPS Setup${RST} — ${DIM}no symlinks, no bloat${RST}"
echo

############ Step 1: Basic environment checks ############
step "Checking helper utilities"
need_pkgs=()
command -v lsusb >/dev/null 2>&1 || need_pkgs+=(usbutils)
if ((${#need_pkgs[@]})); then
  warn "Missing helper package(s): ${need_pkgs[*]}"
  read -r -p "Install helper package(s)? [Y/n] " yn; yn=${yn:-Y}
  if [[ $yn =~ ^[Yy]$ ]]; then
    apt-get update -y && apt-get install -y "${need_pkgs[@]}"
    ok "Helper package(s) installed."
  else warn "Continuing without helper package(s)."; fi
else ok "Environment looks good."; fi
echo

############ Step 2: Detect USB UPS ############
step "Detecting USB UPS devices"
lsusb || true
echo

UPS_HINT="$(lsusb | grep -Ei '0764:0501|cyber|ups|hid|tripp|apc|eaton|liebert|powercom' | head -n1 || true)"
if [[ -n "$UPS_HINT" ]]; then
  ok "USB UPS detected: ${UPS_HINT}"
else
  warn "No obvious UPS found; proceeding with HID driver anyway."
fi

############ Step 3: Parse IDs (if any) ############
VENDORID=""; PRODUCTID=""; SERIAL=""
if [[ -n "$UPS_HINT" ]] && [[ "$UPS_HINT" =~ ID[[:space:]]([0-9a-fA-F]{4}):([0-9a-fA-F]{4}) ]]; then
  VENDORID="${BASH_REMATCH[1]}"
  PRODUCTID="${BASH_REMATCH[2]}"
fi
CYBERPOWER=0
if [[ "${VENDORID,,}" == "0764" ]]; then CYBERPOWER=1; fi

############ Step 4: Ensure minimal NUT packages ############
step "Ensuring minimal NUT packages"
apt_has(){ apt-cache show "$1" >/dev/null 2>&1; }
pkg_present(){ dpkg -s "$1" >/dev/null 2>&1; }

WANT_PKGS=()
if apt_has nut-server && apt_has nut-client && apt_has nut-driver-usb; then
  WANT_PKGS=(nut-server nut-client nut-driver-usb)
else
  WANT_PKGS=(nut)
fi

TO_INSTALL=()
for p in "${WANT_PKGS[@]}"; do pkg_present "$p" || TO_INSTALL+=("$p"); done

if ((${#TO_INSTALL[@]})); then
  info "Packages to install: ${TO_INSTALL[*]}"
  read -r -p "Install now? [Y/n] " yn; yn=${yn:-Y}
  if [[ $yn =~ ^[Yy]$ ]]; then
    apt-get update -y && apt-get install -y "${TO_INSTALL[@]}"
    ok "Installed: ${TO_INSTALL[*]}"
  else
    err "NUT not installed. Aborting."; exit 1
  fi
else ok "NUT packages already present: ${WANT_PKGS[*]}"; fi
echo

############ Step 5: Write minimal config (with backup-once) ############
step "Writing minimal NUT configuration"
UPS_NAME="ups1"; DRIVER="usbhid-ups"; PORT="auto"; DESC="USB UPS"
mkdir -p /etc/nut

for f in ups.conf upsd.conf upsd.users nut.conf; do
  [[ -f /etc/nut/$f && ! -f /etc/nut/$f.bak ]] && cp -a "/etc/nut/$f" "/etc/nut/$f.bak" && info "Backed up $f -> $f.bak"
done

# Default IDs for CyberPower CP1500 AVR if lsusb parsing missed
[[ -z "$VENDORID"  ]] && VENDORID="0764"
[[ -z "$PRODUCTID" ]] && PRODUCTID="0501"

cat >/etc/nut/ups.conf <<EOF
[$UPS_NAME]
  driver = $DRIVER
  port   = $PORT
  desc   = "$DESC"
  vendorid  = "$VENDORID"
  productid = "$PRODUCTID"
$( ((CYBERPOWER)) && echo "  detach_hid = yes" )
  # serial    = "$SERIAL"
EOF

cat >/etc/nut/upsd.conf <<'EOF'
LISTEN 0.0.0.0 3493
# LISTEN :: 3493
EOF

cat >/etc/nut/nut.conf <<'EOF'
MODE=standalone
EOF

MONUSER="monuser"
MONPASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || echo MonPass1234)"
cat >/etc/nut/upsd.users <<EOF
[$MONUSER]
  password = $MONPASS
  upsmon slave
EOF

ok "Configs written."
echo

############ Step 6: Start services ############
step "Starting NUT driver and server"
# Stop anything stale
systemctl stop nut-driver nut-server 2>/dev/null || true
upsdrvctl stop 2>/dev/null || true

# Start driver then server
if systemctl list-unit-files | grep -q '^nut-driver\.service'; then
  systemctl start nut-driver.service || true
else
  upsdrvctl start || true
fi

sleep 1
if systemctl list-unit-files | grep -q '^nut-server\.service'; then
  systemctl restart nut-server.service || true
else
  command -v upsd >/dev/null 2>&1 && upsd || true
fi

sleep 1

# If first probe fails and it's CyberPower, try a clean restart (detach_hid already set)
if command -v upsc >/dev/null 2>&1; then
  if ! upsc "${UPS_NAME}@localhost" >/dev/null 2>&1 && ((CYBERPOWER)); then
    warn "First probe failed; retrying driver start (CyberPower HID quirk)"
    systemctl stop nut-driver 2>/dev/null || true
    upsdrvctl stop 2>/dev/null || true
    sleep 1
    upsdrvctl start || systemctl start nut-driver 2>/dev/null || true
    sleep 1
  fi
fi

# Final check
if command -v upsc >/dev/null 2>&1 && upsc "${UPS_NAME}@localhost" >/dev/null 2>&1; then
  ok "Driver + server running."
else
  warn "upsc probe failed. Check logs: journalctl -u nut-driver -e; journalctl -u nut-server -e"
fi
echo

############ Step 7: Print PeaNUT details ############
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"; HOST_IP=${HOST_IP:-"YOUR_NODE_IP"}
echo -e "${BOLD}PeaNUT / Remote Monitor Details${RST}"
echo -e "  ${BOLD}Host:${RST}        ${HOST_IP}:3493"
echo -e "  ${BOLD}UPS Name:${RST}     ${UPS_NAME}"
echo -e "  ${BOLD}Driver:${RST}       ${DRIVER}"
echo -e "  ${BOLD}Port:${RST}         ${PORT}"
echo -e "  ${BOLD}VendorID:${RST}     ${VENDORID}"
echo -e "  ${BOLD}ProductID:${RST}    ${PRODUCTID}"
[[ -n "$SERIAL"    ]] && echo -e "  ${BOLD}Serial:${RST}       $SERIAL"
echo -e "  ${BOLD}RO User:${RST}      ${MONUSER}"
echo -e "  ${BOLD}RO Pass:${RST}      ${MONPASS}"
echo
echo -e "${DIM}Quick test from another box:${RST}"
echo -e "  upsc ups://${MONUSER}:${MONPASS}@${HOST_IP}/${UPS_NAME}"
echo
ok "Done."