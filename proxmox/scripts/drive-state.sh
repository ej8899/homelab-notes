#!/usr/bin/env bash
#
# drive-state.sh — show hdparm state of drives (a, b, c, d) 
#

# Drives to check
drives=(/dev/sd[a-d])

# Colors
if [[ -t 1 ]]; then
  RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BOLD="\e[1m"; RESET="\e[0m"
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

printf "${BOLD}%-8s %-12s${RESET}\n" "DRIVE" "STATE"
printf "${BOLD}%-8s %-12s${RESET}\n" "-----" "-----"

for d in "${drives[@]}"; do
  if [ -b "$d" ]; then
    state=$(hdparm -C "$d" 2>/dev/null | awk -F: '/state/ {gsub(/^[ \t]+/, "", $2); print $2}')
    case "$state" in
      standby)   color="$GREEN" ;;
      "active/idle") color="$RED" ;;
      *)         color="$YELLOW" ;;
    esac
    printf "%-8s ${color}%-12s${RESET}\n" "$d" "$state"
  else
    printf "%-8s ${YELLOW}%-12s${RESET}\n" "$d" "not present"
  fi
done
