#!/usr/bin/env bash
# cluster-stats-lite.sh — Proxmox cluster-wide stats (NO SSH)
# Shows per-node CPU%, RAM/Disk used/total, uptime, logical CPUs; and cluster totals.
# Requires: jq, awk, bash.

#
# save to any node run as bash ./cluster-stats-lite.sh
#

# Example output:
# NODE                CPU(%)      RAM Used/Total      Disk Used/Total    Uptime(h)    vCPUs
# pve1                 12.3%        32G/64G          500G/1.8T            123         16
# pve2                 45.6%        48G/64G          1.2T/1.8T           4567         32
# Total                57.8%       80G/128G         1.7T/3.6T                       vCPUs: 48
#


set -euo pipefail
command -v jq  >/dev/null || { echo "jq is required"; exit 1; }
command -v awk >/dev/null || { echo "awk is required"; exit 1; }

# Colors (TTY only)
if [[ -t 1 ]]; then
  BOLD="\e[1m"; DIM="\e[2m"; RESET="\e[0m"
  FG_HDR="\e[36m"; FG_OK="\e[32m"; FG_WARN="\e[33m"; FG_BAD="\e[31m"; FG_TOTAL="\e[35m"
else
  BOLD=""; DIM=""; RESET=""; FG_HDR=""; FG_OK=""; FG_WARN=""; FG_BAD=""; FG_TOTAL=""
fi

json="$(pvesh get /cluster/resources --type node --output-format=json)"
mapfile -t NODES < <(echo "$json" | jq -r '.[].node')

printf "${FG_HDR}${BOLD}%-14s %8s %18s %20s %10s %8s${RESET}\n" \
  "NODE" "CPU(%)" "RAM Used/Total" "Disk Used/Total" "Uptime(h)" "vCPUs"

tot_cpu_weighted=0
tot_maxcpu=0
tot_mem_used=0
tot_mem_total=0
tot_disk_used=0
tot_disk_total=0

for n in "${NODES[@]}"; do
  row="$(echo "$json" | jq -r --arg n "$n" '.[] | select(.node==$n) |
    { node, cpu, maxcpu, mem, maxmem, disk, maxdisk, uptime }')"

  cpu_frac=$(jq -r '.cpu // 0' <<<"$row")
  maxcpu=$(jq -r '.maxcpu // 0' <<<"$row")
  mem_used=$(jq -r '.mem // 0' <<<"$row")
  mem_total=$(jq -r '.maxmem // 0' <<<"$row")
  disk_used=$(jq -r '.disk // 0' <<<"$row")
  disk_total=$(jq -r '.maxdisk // 0' <<<"$row")
  uptime=$(jq -r '.uptime // 0' <<<"$row")

  cpu_pct=$(awk -v c="$cpu_frac" 'BEGIN{printf "%.1f", c*100}')
  mem_used_g=$(awk -v b="$mem_used" 'BEGIN{printf "%.0f", b/1073741824}')
  mem_total_g=$(awk -v b="$mem_total" 'BEGIN{printf "%.0f", b/1073741824}')
  disk_used_g=$(awk -v b="$disk_used" 'BEGIN{printf "%.0f", b/1073741824}')
  disk_total_g=$(awk -v b="$disk_total" 'BEGIN{printf "%.0f", b/1073741824}')
  up_hours=$(( uptime/3600 ))

  # Color CPU%, and also RAM/Disk utilization
  cpu_int=${cpu_pct%.*}; cpu_color="$FG_OK"
  (( cpu_int >= 80 )) && cpu_color="$FG_BAD" || { (( cpu_int >= 50 )) && cpu_color="$FG_WARN"; }

  ram_pct=0; [[ $mem_total -gt 0 ]] && ram_pct=$(( mem_used*100/mem_total ))
  disk_pct=0; [[ $disk_total -gt 0 ]] && disk_pct=$(( disk_used*100/disk_total ))
  ram_color="$FG_OK"; (( ram_pct >= 80 )) && ram_color="$FG_BAD" || { (( ram_pct >= 60 )) && ram_color="$FG_WARN"; }
  disk_color="$FG_OK"; (( disk_pct >= 85 )) && disk_color="$FG_BAD" || { (( disk_pct >= 70 )) && disk_color="$FG_WARN"; }

  printf "%-14s ${cpu_color}%8s${RESET} ${ram_color}%8s/%-9s${RESET} ${disk_color}%8s/%-9s${RESET} %10s %8s\n" \
    "$n" "$cpu_pct" \
    "${mem_used_g}G" "${mem_total_g}G" \
    "${disk_used_g}G" "${disk_total_g}G" \
    "$up_hours" "$maxcpu"

  # Totals
  tot_cpu_weighted=$(awk -v tot="$tot_cpu_weighted" -v cf="$cpu_frac" -v mc="$maxcpu" 'BEGIN{printf "%.6f", tot + (cf*mc)}')
  tot_maxcpu=$(( tot_maxcpu + maxcpu ))
  tot_mem_used=$(( tot_mem_used + mem_used ))
  tot_mem_total=$(( tot_mem_total + mem_total ))
  tot_disk_used=$(( tot_disk_used + disk_used ))
  tot_disk_total=$(( tot_disk_total + disk_total ))
done

cpu_total_pct="0.0"
(( tot_maxcpu > 0 )) && cpu_total_pct=$(awk -v w="$tot_cpu_weighted" -v m="$tot_maxcpu" 'BEGIN{printf "%.1f", (w/m)*100}')
mem_used_g=$(awk -v b="$tot_mem_used" 'BEGIN{printf "%.0f", b/1073741824}')
mem_total_g=$(awk -v b="$tot_mem_total" 'BEGIN{printf "%.0f", b/1073741824}')
disk_used_g=$(awk -v b="$tot_disk_used" 'BEGIN{printf "%.0f", b/1073741824}')
disk_total_g=$(awk -v b="$tot_disk_total" 'BEGIN{printf "%.0f", b/1073741824}')

echo -e "${DIM}-------------------------------------------------------------------------------------------------------------${RESET}"
printf "${FG_TOTAL}${BOLD}%-14s %8s %8s/%-9s %8s/%-9s  vCPUs: %d${RESET}\n" \
  "TOTAL (util)" "$cpu_total_pct" "${mem_used_g}G" "${mem_total_g}G" "${disk_used_g}G" "${disk_total_g}G" "$tot_maxcpu"
