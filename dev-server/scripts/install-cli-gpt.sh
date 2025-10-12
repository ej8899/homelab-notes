#!/usr/bin/env bash
# install-cli-gpt.sh — one-shot installer for a minimal, colorized OpenAI CLI ("gpt")
# Usage:
#   chmod +x install-gpt-cli.sh
#   sudo ./install-gpt-cli.sh
# Then:
#   export OPENAI_API_KEY="sk-..."   # add to your shell profile to persist
#   gpt "Explain SnapRAID vs MergerFS in 3 bullets"
#   echo "Summarize this file" | gpt
set -euo pipefail

# ---------- helpers ----------
have() { command -v "$1" >/dev/null 2>&1; }

msg()  { printf "%b\n" "$*"; }
ok()   { msg "\033[1;32m✔\033[0m $*"; }
warn() { msg "\033[1;33m⚠\033[0m $*"; }
err()  { msg "\033[1;31m✖\033[0m $*" >&2; }

pkg_install() {
  local need=("$@")
  # Detect package manager
  if have apt-get; then
    sudo apt-get update -y
    sudo apt-get install -y "${need[@]}"
  elif have apt; then
    sudo apt update -y
    sudo apt install -y "${need[@]}"
  elif have dnf; then
    sudo dnf install -y "${need[@]}"
  elif have yum; then
    sudo yum install -y "${need[@]}"
  elif have pacman; then
    sudo pacman -Sy --noconfirm "${need[@]}"
  elif have apk; then
    sudo apk add --no-cache "${need[@]}"
  elif have brew; then
    brew install "${need[@]}"
  else
    err "Could not detect a supported package manager. Install dependencies manually: ${need[*]}"
    exit 1
  fi
}

need_deps=(curl jq)
to_install=()
for d in "${need_deps[@]}"; do
  have "$d" || to_install+=("$d")
done

if ((${#to_install[@]})); then
  warn "Missing deps: ${to_install[*]} — installing…"
  pkg_install "${to_install[@]}"
else
  ok "Dependencies present: curl, jq"
fi

# ---------- install gpt ----------
target="/usr/local/bin/gpt"
tmpfile="$(mktemp)"
cat >"$tmpfile" <<"EOF"
#!/usr/bin/env bash
# gpt — minimal colorized CLI for OpenAI Chat Completions (no history)
# Usage:
#   gpt "your prompt here"
#   echo "text" | gpt
# Options:
#   -m MODEL        Set model (default: gpt-4o-mini)
#   -s "SYSTEM"     Set a custom system prompt
#   --no-color      Disable colorized output
# Env:
#   OPENAI_API_KEY  (required)
set -euo pipefail

# --------- defaults & args ---------
MODEL="${MODEL:-gpt-4o-mini}"
SYSTEM_DEFAULT="You are a concise, helpful assistant."
SYSTEM_PROMPT="${SYSTEM_PROMPT:-$SYSTEM_DEFAULT}"
COLOR=1

args=()
while (( $# )); do
  case "$1" in
    -m) MODEL="${2:-}"; shift 2;;
    -s) SYSTEM_PROMPT="${2:-}"; shift 2;;
    --no-color) COLOR=0; shift;;
    --) shift; break;;
    -h|--help)
      cat <<USAGE
gpt — minimal OpenAI CLI

Usage:
  gpt "prompt text"
  echo "text" | gpt
Options:
  -m MODEL        Choose model (default: $MODEL)
  -s "SYSTEM"     Custom system prompt
  --no-color      Disable color output
Env:
  OPENAI_API_KEY  Your API key (required)
USAGE
      exit 0
      ;;
    *) args+=("$1"); shift;;
  esac
done

PROMPT_FROM_ARGS="${args[*]:-}"

if [ -t 0 ]; then
  PROMPT="$PROMPT_FROM_ARGS"
else
  PROMPT="$(cat)"
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  printf "\033[1;31m✖ OPENAI_API_KEY not set.\033[0m Export it first:\n  export OPENAI_API_KEY=\"sk-...\"\n" >&2
  exit 1
fi

if [ -z "$PROMPT" ]; then
  printf "\033[1;33m⚠ No prompt provided.\033[0m Try: gpt \"Say hello\"\n" >&2
  exit 1
fi

# Colors
if [ "$COLOR" -eq 1 ] && [ -t 1 ]; then
  BOLD="\033[1m"; DIM="\033[2m"; GREEN="\033[32m"; BLUE="\033[34m"; RESET="\033[0m"
else
  BOLD=""; DIM=""; GREEN=""; BLUE=""; RESET=""
fi

# --------- request ---------
URL="https://api.openai.com/v1/chat/completions"

# Build JSON with jq for proper escaping
payload="$(jq -n --arg m "$MODEL" --arg sys "$SYSTEM_PROMPT" --arg p "$PROMPT" '{
  model: $m,
  messages: [
    {role:"system", content:$sys},
    {role:"user", content:$p}
  ]
}')"

response="$(curl -sS "$URL" \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$payload" || true)"

# Detect API errors
if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
  code="$(echo "$response" | jq -r '.error.code // empty')"
  msg="$(echo "$response" | jq -r '.error.message // "Unknown error"')"
  printf "\033[1;31m✖ API error\033[0m %s\n" "$([ -n "$code" ] && echo "($code)")" >&2
  printf "%s\n" "$msg" >&2
  exit 2
fi

content="$(echo "$response" | jq -r '.choices[0].message.content // empty')"

if [ -z "$content" ]; then
  printf "\033[1;33m⚠ No content returned.\033[0m\n" >&2
  exit 3
fi

# Header + content
printf "${DIM}${BLUE}[%s | %s]${RESET}\n" "$MODEL" "$(date +'%Y-%m-%d %H:%M:%S')" >&2
printf "${BOLD}${GREEN}%s${RESET}\n" "$content"
EOF

sudo install -m 0755 "$tmpfile" "$target"
rm -f "$tmpfile"
ok "Installed gpt -> $target"

# ---------- post install tips ----------
cat <<'TIP'

Next steps:
  1) Set your API key for this shell (and add to your profile to persist):
       export OPENAI_API_KEY="sk-REPLACE-ME"
     Add that line to ~/.bashrc or ~/.zshrc to keep it permanent.

  2) Try it:
       gpt "Give me 3 bullets on SnapRAID vs MergerFS"
       echo "Explain union filesystems in 2 sentences" | gpt
       gpt -m gpt-4o "Write a one-liner to show top disk I/O"

  3) Disable color if you’re scripting:
       gpt --no-color "Plain output for scripts"

Uninstall:
  sudo rm -f /usr/local/bin/gpt
TIP

ok "All done."
