#!/usr/bin/env bash
# Toggle laptop screen power by reading /sys/class/backlight/*/bl_power
# Usage:
#   ./toggle-screen.sh        # toggle
#   ./toggle-screen.sh on     # force on
#   ./toggle-screen.sh off    # force off
set -euo pipefail

action="${1:-toggle}"

# Find backlight power files
shopt -s nullglob
files=(/sys/class/backlight/*/bl_power)
if ((${#files[@]} == 0)); then
  echo "No backlight controls found at /sys/class/backlight/*/bl_power"
  exit 1
fi

# Need root to write sysfs
if [[ $EUID -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -- "$0" "$action"
  else
    echo "Please run as root (or install sudo)."
    exit 1
  fi
fi

# Read current state from the first device (0=on, 1=off on most drivers)
current="$(<"${files[0]}")"

case "$action" in
  on)     target=0 ;;
  off)    target=1 ;;
  toggle) target=$([[ "$current" == "0" ]] && echo 1 || echo 0) ;;
  *)      echo "Usage: $0 [on|off|toggle]"; exit 1 ;;
esac

# Write to all detected backlight devices
for f in "${files[@]}"; do
  echo "$target" > "$f"
done

[[ "$target" -eq 0 ]] && echo "Screen turned ON." || echo "Screen turned OFF."
