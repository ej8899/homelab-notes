#!/usr/bin/env bash
#
# drive-state-auto.sh — show hdparm state of all /dev/sdX drives with colors
#

# Colors
if [[ -t 1 ]]; then
  RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BOLD="\e[1m"; RESET="\e[0m"
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

printf "${BOLD}%-8s %-12s${RESET}\n" "DRIVE" "STATE"
printf "${BOLD}%-8s %-12s${RESET}\n" "-----" "-----"

for d in /dev/sd?; do
  if [ -b "$d" ]; then
    state=$(hdparm -C "$d" 2>/dev/null | awk -F: '/state/ {gsub(/^[ \t]+/, "", $2); print $2}')
    if [[ -z "$state" ]]; then
      state="unknown"
    fi

    case "$state" in
      standby)       color="$GREEN" ;;
      "active/idle") color="$RED" ;;
      *)             color="$YELLOW" ;;
    esac

    printf "%-8s ${color}%-12s${RESET}\n" "$d" "$state"
  fi
done
