#!/usr/bin/env bash
# diskdash.sh — live disk dashboard for Proxmox/Debian
# Shows: disk | id (model/serial) | temp | rB/s | wB/s | errors | fs | size | used | free
# Notes:
#  - Run as root for SMART temps and error stats.
#  - NVMe + SATA supported. USB/RAID virtual devices may lack SMART/temps.
#  - ZFS usage is per-pool, not per-disk; we show mounted filesystems’ usage sums.
#
# bash diskdash.sh [-r <seconds>]

REFRESH="${REFRESH:-1}"   # seconds between updates
COLS=$(tput cols 2>/dev/null || echo 120)
PAUSED=0

# Optional CLI: -r <seconds>
while getopts ":r:" opt; do
  case $opt in
    r) REFRESH="$OPTARG" ;;
  esac
done

# Colors
BOLD=$(tput bold 2>/dev/null); DIM=$(tput dim 2>/dev/null); RESET=$(tput sgr0 2>/dev/null)
C_HDR=$(tput setaf 6 2>/dev/null)       # cyan
C_OK=$(tput setaf 2 2>/dev/null)        # green
C_WARN=$(tput setaf 3 2>/dev/null)      # yellow
C_BAD=$(tput setaf 1 2>/dev/null)       # red
C_MUTED=$(tput setaf 7 2>/dev/null)     # gray/white

declare -A PREV_R PREV_W PREV_T PREV_SS

human() { # bytes -> human
  local b=$1; local d=1024; local s=0; local u=(B KiB MiB GiB TiB PiB)
  while (( b >= d && s < ${#u[@]}-1 )); do b=$(( b/d )); s=$(( s+1 )); done
  printf "%d %s" "$b" "${u[$s]}"
}

get_disks() {
  # List kernel block "disk" devices (exclude loop/ram)
  lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -E -v '^(loop|ram)'
}

get_sector_size() {
  local d=$1
  blockdev --getss "/dev/$d" 2>/dev/null || echo 512
}

read_rw_bytes() {
  # Output: "<read_bytes> <written_bytes>" as pure integers
  local d=$1 ss=$2
  if [[ -r "/sys/block/$d/stat" ]]; then
    # Grab sector counts only, do the multiplication in bash (integer math)
    local sec_r sec_w
    read -r sec_r sec_w < <(awk '{print $3, $7}' "/sys/block/$d/stat")
    [[ -z "$sec_r" ]] && sec_r=0
    [[ -z "$sec_w" ]] && sec_w=0
    echo $(( sec_r * ss )) $(( sec_w * ss ))
  else
    echo "0 0"
  fi
}


get_model_serial() {
  local d=$1
  local model serial
  model=$(lsblk -dn -o MODEL "/dev/$d" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' )
  serial=$(lsblk -dn -o SERIAL "/dev/$d" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' )
  [[ -z "$model" ]] && model="N/A"
  [[ -z "$serial" ]] && serial="N/A"
  printf "%s / %s" "$model" "$serial"
}

get_temp() {
  local d=$1
  local t="N/A"

  if [[ "$d" =~ ^nvme ]]; then
    # NVMe: nvme smart-log reports in Celsius
    t=$(nvme smart-log "/dev/$d" 2>/dev/null | awk '/^temperature/ {print $3}' | head -n1)
    [[ -z "$t" ]] && t="N/A"
  else
    # SATA/SAS via smartctl -A; prefer attribute 194 or "Temperature" lines
    t=$(smartctl -A "/dev/$d" 2>/dev/null | awk '
      $1==194 && ($2 ~ /Temperature/ || $2 ~ /Temperature_Celsius/) {print $10}
      /Temperature_Celsius/ && $10 ~ /^[0-9]+$/ {print $10}
      /^194/ && $10 ~ /^[0-9]+$/ {print $10}
    ' | head -n1)
    if [[ -z "$t" ]]; then
      t=$(smartctl -H "/dev/$d" 2>/dev/null | awk -F': ' '/Current Drive Temperature|Temperature_Celsius/ {print $2}' | sed 's/[^0-9]*//g' | head -n1)
      [[ -z "$t" ]] && t="N/A"
    fi
  fi
  # --- sanitize: keep only the first integer; else N/A ---
  t=$(grep -oE '[0-9]+' <<<"$t" | head -n1)
  [[ -z "$t" ]] && t="N/A"
  echo "$t"
}


get_errors() {
  local d=$1
  local e="N/A"
  if [[ "$d" =~ ^nvme ]]; then
    # nvme smart-log media_errors
    e=$(nvme smart-log "/dev/$d" 2>/dev/null | awk '/media_errors/ {print $3}' | head -n1)
    [[ -z "$e" ]] && e="N/A"
  else
    # SATA typical: attribute 199 UDMA_CRC_Error_Count; fallback to grown_defects, etc.
    e=$(smartctl -A "/dev/$d" 2>/dev/null | awk '
      $1==199 && $2 ~ /UDMA_CRC_Error_Count/ {print $10}
    ' | head -n1)
    if [[ -z "$e" ]]; then
      e=$(smartctl -A "/dev/$d" 2>/dev/null | awk '
        /Reallocated_Sector_Ct/ {cand1=$10}
        /Current_Pending_Sector/ {cand2=$10}
        END {
          if (cand1=="" && cand2=="") print "";
          else {
            if (cand1=="") cand1=0;
            if (cand2=="") cand2=0;
            print cand1 + cand2
          }
        }' )
    fi
    [[ -z "$e" ]] && e="N/A"
  fi
  echo "$e"
}

# For FS + usage: aggregate mounted children partitions
get_fs_and_usage() {
  local d=$1
  local used_sum=0
  local free_sum=0
  local -a fs_set=()

  # Build a quick parent lookup (child -> parent)
  declare -A PK
  while read -r name pk; do
    [[ -n "$name" ]] && PK["$name"]="$pk"
  done < <(lsblk -rno NAME,PKNAME)

  # Walk all mounted nodes; include if ancestor is our disk
  while IFS= read -r line; do
    # NAME TYPE MOUNTPOINT FSTYPE
    read -r name type mnt fs <<<"$line"
    [[ -z "$mnt" || "$mnt" == "-" ]] && continue

    # Ascend parents until root; include if we hit $d
    cur="$name"
    while [[ -n "$cur" ]]; do
      if [[ "$cur" == "$d" ]]; then
        # Sum df for this mount
        local u a
        read -r u a < <(df -B1 --output=used,avail "$mnt" 2>/dev/null | tail -n1)
        [[ -n "$u" ]] && used_sum=$((used_sum + u))
        [[ -n "$a" ]] && free_sum=$((free_sum + a))
        # Track fs type
        if [[ -n "$fs" && "$fs" != "-" ]]; then
          [[ " ${fs_set[*]} " != *" $fs "* ]] && fs_set+=("$fs")
        fi
        break
      fi
      cur="${PK[$cur]}"
    done
  done < <(lsblk -rno NAME,TYPE,MOUNTPOINT,FSTYPE)

  local fs_list="—"
  ((${#fs_set[@]})) && fs_list=$(IFS=,; echo "${fs_set[*]}")

  echo "$fs_list|$used_sum|$free_sum"
}


get_size_bytes() {
  local d=$1
  lsblk -bdn -o SIZE "/dev/$d" 2>/dev/null
}

temp_color() {
  local t=$1
  [[ "$t" == "N/A" ]] && { echo "$C_MUTED$t$RESET"; return; }
  if (( t < 40 )); then echo "${C_OK}${t}°C${RESET}"
  elif (( t < 50 )); then echo "${C_WARN}${t}°C${RESET}"
  else echo "${C_BAD}${t}°C${RESET}"; fi
}

print_header() {
  printf "%s%sDISK HEALTH DASHBOARD%s  (refresh: %ss)\n" "$BOLD" "$C_HDR" "$RESET" "$REFRESH"
  printf "%s\n" "$(printf '━%.0s' $(seq 1 $(( COLS>120?120:COLS )) ))"
  printf "%s%-9s %-30s %8s %12s %12s %8s %-14s %10s %10s %s\n" \
  "$BOLD" "DISK" "IDENTIFICATION" "TEMP" "READ/s" "WRITE/s" "ERRORS" "FS" "SIZE" "USED" "FREE$RESET"
}

main_loop() {
  while true; do
    tput civis 2>/dev/null
    tput clear 2>/dev/null || echo -ne "\033c"

   # Toggle pause with Space; q to quit
   if read -rsn1 -t 0.05 key; then
      [[ "$key" == " " ]] && PAUSED=$((1-PAUSED))
      [[ "$key" == "q" ]] && { tput cnorm 2>/dev/null; exit 0; }
   fi
   if (( PAUSED )); then
     printf "[PAUSED] Press space to resume, q to quit\r"
     sleep 0.2
     continue
   fi


    print_header

    local disks; IFS=$'\n' read -r -d '' -a disks < <( { get_disks; echo; } )
    local total_drives=0 temp_sum=0 temp_cnt=0 total_size=0 sum_used=0 sum_free=0

    for d in "${disks[@]}"; do
      [[ -z "$d" ]] && continue
      total_drives=$((total_drives+1))

      local ss=$(get_sector_size "$d")
      local cur_r cur_w; read -r cur_r cur_w < <(read_rw_bytes "$d" "$ss")
      local now=$(date +%s)

      # Throughput calc
      local prev_r=${PREV_R[$d]:-0} prev_w=${PREV_W[$d]:-0} prev_t=${PREV_T[$d]:-$now}
      local dt=$(( now - prev_t )); (( dt <= 0 )) && dt=1
      local rps=$(( (cur_r - prev_r) / dt )); (( rps < 0 )) && rps=0
      local wps=$(( (cur_w - prev_w) / dt )); (( wps < 0 )) && wps=0

      PREV_R[$d]=$cur_r; PREV_W[$d]=$cur_w; PREV_T[$d]=$now; PREV_SS[$d]=$ss

      local id="$(get_model_serial "$d")"
      local raw_temp="$(get_temp "$d")"
      local tc="$(temp_color "$raw_temp")"
      if [[ "$raw_temp" != "N/A" ]]; then temp_sum=$((temp_sum + raw_temp)); temp_cnt=$((temp_cnt+1)); fi

      local errs="$(get_errors "$d")"

      local fs_used fs_free fs_list
      IFS='|' read -r fs_list fs_used fs_free < <(get_fs_and_usage "$d")

      local sz=$(get_size_bytes "$d"); [[ -z "$sz" ]] && sz=0
      total_size=$((total_size + sz))
      sum_used=$((sum_used + fs_used))
      sum_free=$((sum_free + fs_free))

      # Pretty prints
      local rps_h=$(human "$rps")
      local wps_h=$(human "$wps")
      local sz_h=$(human "$sz")
      local usd_h=$(human "$fs_used")
      local fre_h=$(human "$fs_free")

      # Color for errors
      local errs_c="$errs"
      if [[ "$errs" == "N/A" ]]; then errs_c="${C_MUTED}N/A${RESET}"
      elif [[ "$errs" =~ ^[0-9]+$ ]]; then
        if (( errs == 0 )); then errs_c="${C_OK}0${RESET}"
        elif (( errs < 10 )); then errs_c="${C_WARN}${errs}${RESET}"
        else errs_c="${C_BAD}${errs}${RESET}"
        fi
      else errs_c="${C_MUTED}${errs}${RESET}"; fi
      local id_trimmed="${id:0:30}"


      printf "%-9s %-30s %8s %12s %12s %8s %-14.14s %10s %10s %10s\n" \
            "$d" "$id_trimmed" "$tc" "$rps_h" "$wps_h" "$errs_c" "$fs_list" "$sz_h" "$usd_h" "$fre_h"
    done

    # Summary
    local avg_temp="N/A"
    if (( temp_cnt > 0 )); then avg_temp=$(( temp_sum / temp_cnt )); fi
    local avg_temp_c=$(temp_color "$avg_temp")
    local total_size_h=$(human "$total_size")
    local total_free_h=$(human "$sum_free")

    printf "%s\n" "$(printf '─%.0s' $(seq 1 $(( COLS>120?120:COLS )) ))"
    printf "%sTotal drives:%s %d   %sAvg Temp:%s %s   %sTotal Size:%s %s   %sTotal Free:%s %s\n" \
      "$BOLD" "$RESET" "$total_drives" \
      "$BOLD" "$RESET" "$avg_temp_c" \
      "$BOLD" "$RESET" "$total_size_h" \
      "$BOLD" "$RESET" "$total_free_h"

    printf "%sNotes:%s temps/errors via SMART; FS usage sums mounted child partitions. ZFS usage is pool-level.\n" "$DIM" "$RESET"

    sleep "$REFRESH"
  done
}

# Sanity checks (non-fatal)
command -v lsblk >/dev/null || { echo "lsblk required"; exit 1; }
command -v smartctl >/dev/null || echo "Warning: smartmontools not installed; temps/errors may be N/A" >&2
command -v nvme >/dev/null || echo "Note: nvme-cli not installed; NVMe temps/errors may be N/A" >&2

main_loop