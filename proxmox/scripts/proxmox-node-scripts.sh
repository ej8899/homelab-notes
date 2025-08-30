#!/usr/bin/env bash
#
# homelab-scripts-sync
#
# Pull only homelab-notes/proxmox/scripts and deploy its *contents* into /opt/homelab
set -euo pipefail

# --- Config (override via env if desired) ---
REPO_URL="${REPO_URL:-https://github.com/ej8899/homelab-notes.git}" # or git@github.com:ej8899/homelab-notes.git
SPARSE_PATH="${SPARSE_PATH:-proxmox/scripts}"   # subfolder in repo to deploy
CACHE_DIR="${CACHE_DIR:-/opt/.homelab-cache}"   # where the sparse repo lives
TARGET_DIR="${TARGET_DIR:-/opt/homelab}"        # where scripts should be copied (contents only)
RSYNC_DELETE_FLAG="${RSYNC_DELETE_FLAG:---delete}"  # set to "" to keep extra files in TARGET_DIR
FORCE_CLEAN="${FORCE_CLEAN:-0}"                 # set to 1 to auto-remove a stray .git in TARGET_DIR

# --- Ensure git present ---
if ! command -v git >/dev/null 2>&1; then
  echo ">> Installing git..."
  apt-get update -y
  apt-get install -y git
fi

# --- Safety check: don't mix a git repo into TARGET_DIR (we deploy plain files there) ---
if [ -d "$TARGET_DIR/.git" ]; then
  if [ "$FORCE_CLEAN" = "1" ]; then
    echo ">> WARNING: removing git repo found in $TARGET_DIR"
    rm -rf "$TARGET_DIR/.git"
  else
    echo "!! $TARGET_DIR contains a .git directory."
    echo "   Move it aside (e.g., mv $TARGET_DIR ${TARGET_DIR}.bak) or re-run with FORCE_CLEAN=1"
    exit 1
  fi
fi

# --- Prepare cache repo ---
mkdir -p "$CACHE_DIR"
if [ ! -d "$CACHE_DIR/.git" ]; then
  echo ">> Initial sparse clone of $REPO_URL into $CACHE_DIR"
  git clone --filter=blob:none --sparse "$REPO_URL" "$CACHE_DIR"
  cd "$CACHE_DIR"
  # Enable sparse checkout (cone if supported)
  if git sparse-checkout init --cone 2>/dev/null; then
    git sparse-checkout set "$SPARSE_PATH"
  else
    git config core.sparseCheckout true
    echo "$SPARSE_PATH/*" > .git/info/sparse-checkout
    git read-tree -mu HEAD
  fi
else
  cd "$CACHE_DIR"
  current_url="$(git remote get-url origin || true)"
  if [ "$current_url" != "$REPO_URL" ]; then
    echo ">> Updating 'origin' remote to $REPO_URL"
    git remote set-url origin "$REPO_URL"
  fi
  # ensure our sparse path is selected
  if ! git sparse-checkout list 2>/dev/null | grep -qx "$SPARSE_PATH"; then
    git sparse-checkout set "$SPARSE_PATH"
  fi
fi

echo ">> Pulling latest changes..."
git pull --ff-only

# --- Source (the subfolder in the cache) and target prep ---
SRC_DIR="$CACHE_DIR/$SPARSE_PATH"
mkdir -p "$TARGET_DIR"

# --- Deploy *contents* of SRC_DIR into TARGET_DIR ---
# Trailing slash on SRC_DIR copies its contents (not the directory itself)
echo ">> Syncing $SRC_DIR/ -> $TARGET_DIR"
rsync -a $RSYNC_DELETE_FLAG "$SRC_DIR/" "$TARGET_DIR/"

# --- Ensure .sh are executable (in case exec bits aren't set in repo) ---
find "$TARGET_DIR" -type f -name "*.sh" -exec chmod +x {} +

echo ">> Done."
echo "   Cache repo:    $CACHE_DIR  (sparse: $SPARSE_PATH)"
echo "   Deployed to:   $TARGET_DIR  (files only)"
echo "   Update anytime by re-running:  homelab-script-sync"
