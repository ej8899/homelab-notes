#!/usr/bin/env bash
#
# homelab-scripts-sync
#

# Pull only homelab-notes/proxmox/scripts and deploy its *contents* into /opt/homelab
# Usage (defaults OK):
#   chmod +x /usr/local/bin/homelab-scripts-sync
#   /usr/local/bin/homelab-scripts-sync
#
# Overrides:
#   REPO_URL=git@github.com:ej8899/homelab-notes.git \
#   SPARSE_PATH=proxmox/scripts \
#   CACHE_DIR=/opt/.homelab-cache \
#   TARGET_DIR=/opt/homelab \
#   RSYNC_DELETE_FLAG= \
#   FORCE_CLEAN=1 \
#     homelab-scripts-sync
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
trap 'err "An error occurred on line ${BASH_LINENO[0]}"; exit 1' ERR

# ---------- Config ----------
REPO_URL="${REPO_URL:-https://github.com/ej8899/homelab-notes.git}"   # or git@github.com:ej8899/homelab-notes.git
SPARSE_PATH="${SPARSE_PATH:-proxmox/scripts}"                         # subfolder in repo to deploy
CACHE_DIR="${CACHE_DIR:-/opt/.homelab-cache}"                         # where the sparse repo lives
TARGET_DIR="${TARGET_DIR:-/opt/homelab}"                              # where scripts should be copied (contents only)
RSYNC_DELETE_FLAG="${RSYNC_DELETE_FLAG:---delete}"                    # set to "" to keep extra files in TARGET_DIR
FORCE_CLEAN="${FORCE_CLEAN:-0}"                                       # set to 1 to remove accidental .git in TARGET_DIR

step "Config"
echo -e "${DIM}REPO_URL     :${RESET} ${REPO_URL}"
echo -e "${DIM}SPARSE_PATH  :${RESET} ${SPARSE_PATH}"
echo -e "${DIM}CACHE_DIR    :${RESET} ${CACHE_DIR}"
echo -e "${DIM}TARGET_DIR   :${RESET} ${TARGET_DIR}"
echo -e "${DIM}RSYNC_DELETE :${RESET} ${RSYNC_DELETE_FLAG:-<disabled>}"
echo -e "${DIM}FORCE_CLEAN  :${RESET} ${FORCE_CLEAN}"

# ---------- Helpers ----------
need_pkg () {
  dpkg -s "$1" >/dev/null 2>&1 || { step "Install $1"; apt-get update -y && apt-get install -y "$1"; ok "$1 installed"; }
}

# ---------- Ensure deps ----------
need_pkg git
need_pkg rsync

# ---------- Safety: ensure TARGET is not a git repo ----------
if [[ -d "$TARGET_DIR/.git" ]]; then
  if [[ "$FORCE_CLEAN" == "1" ]]; then
    warn "$TARGET_DIR contains a Git repo; removing .git because FORCE_CLEAN=1"
    rm -rf "$TARGET_DIR/.git"
  else
    err "$TARGET_DIR contains a .git directory. Move it aside (e.g., mv $TARGET_DIR ${TARGET_DIR}.bak) or re-run with FORCE_CLEAN=1"
    exit 1
  fi
fi

# ---------- Prepare cache repo ----------
mkdir -p "$CACHE_DIR"
if [[ ! -d "$CACHE_DIR/.git" ]]; then
  step "Initial sparse clone"
  info "Cloning ${REPO_URL} -> ${CACHE_DIR}"
  git clone --filter=blob:none --sparse "$REPO_URL" "$CACHE_DIR"
  cd "$CACHE_DIR"
  if git sparse-checkout init --cone >/dev/null 2>&1; then
    git sparse-checkout set "$SPARSE_PATH"
  else
    warn "Cone mode not available; using legacy sparse-checkout"
    git config core.sparseCheckout true
    echo "$SPARSE_PATH/*" > .git/info/sparse-checkout
    git read-tree -mu HEAD
  fi
  ok "Sparse clone ready"
else
  cd "$CACHE_DIR"
  current_url="$(git remote get-url origin || true)"
  if [[ "$current_url" != "$REPO_URL" ]]; then
    step "Adjust remote URL"
    info "origin: $current_url -> $REPO_URL"
    git remote set-url origin "$REPO_URL"
    ok "Remote updated"
  fi
  # Ensure sparse path selected
  if ! git sparse-checkout list 2>/dev/null | grep -qx "$SPARSE_PATH"; then
    step "Update sparse paths"
    git sparse-checkout set "$SPARSE_PATH"
    ok "Sparse path set to ${SPARSE_PATH}"
  fi
fi

# ---------- Pull latest ----------
step "Fetch latest"
git fetch --quiet
git pull --ff-only
ok "Repo up to date at ${DIM}$(git rev-parse --short HEAD)${RESET}"

# ---------- Validate source dir ----------
SRC_DIR="${CACHE_DIR}/${SPARSE_PATH}"
if [[ ! -d "$SRC_DIR" ]]; then
  err "Sparse source not found: ${SRC_DIR}"
  exit 1
fi
info "Source: ${SRC_DIR}"

# ---------- Deploy contents ----------
mkdir -p "$TARGET_DIR"
step "Sync → ${TARGET_DIR}"
rsync -a ${RSYNC_DELETE_FLAG} "${SRC_DIR}/" "${TARGET_DIR}/"
ok "Files synced"

# ---------- Ensure executables ----------
step "Ensure executable bits"
find "$TARGET_DIR" -type f -name "*.sh" -print0 | xargs -0 -r chmod +x
ok "Executable bits applied to *.sh"

# ---------- Summary ----------
step "Summary"
files_count="$(find "$TARGET_DIR" -type f | wc -l | tr -d ' ')"
echo -e "${CYAN}Cache repo   :${RESET} ${CACHE_DIR} ${DIM}(sparse: ${SPARSE_PATH})${RESET}"
echo -e "${CYAN}Deployed to  :${RESET} ${TARGET_DIR}"
echo -e "${CYAN}File count   :${RESET} ${files_count}"
ok "Done. Re-run this script any time to update."
