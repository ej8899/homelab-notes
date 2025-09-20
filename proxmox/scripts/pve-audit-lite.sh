#!/usr/bin/env bash
# pve-audit-lite.sh — Plain-text, colorized VM/CT audit for a Proxmox cluster
# - Run on any PVE node (needs pvesh and /etc/pve mounted)
# - No files created; prints to screen only
# - Works even if other nodes are offline (reads pmxcfs + cluster resources)
# - Uses jq if available; otherwise falls back to a built-in parser

set -euo pipefail

# ---------- colors ----------
if [ -t 1 ]; then
  RED="\e[31m"; GRN="\e[32m"; YLW="\e[33m"; BLU="\e[34m"; MAG="\e[35m"; CYN="\e[36m"
  BLD="\e[1m"; DIM="\e[2m"; RST="\e[0m"
else
  RED=""; GRN=""; YLW=""; BLU=""; MAG=""; CYN=""; BLD=""; DIM=""; RST=""
fi

die(){ echo -e "${RED}ERROR:${RST} $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

[ -x /usr/bin/pvesh ] || die "pvesh not found (run on a Proxmox node)."
[ -d /etc/pve ] || die "/etc/pve not mounted; pmxcfs unavailable."

ts="$(date +'%F %T')"
echo -e "${BLU}${BLD}Proxmox Cluster Audit${RST} ${DIM}[$ts]${RST}\n"

# ---------- HA resource map (vm:100 / ct:101) ----------
declare -A HA
if pvesh get /cluster/ha/resources --output-format json >/dev/null 2>&1; then
  if have jq; then
    while read -r sid; do HA["$sid"]=1; done < <(pvesh get /cluster/ha/resources --output-format json | jq -r '.[].sid')
  else
    # crude parse for "sid":"vm:100"
    while read -r sid; do HA["$sid"]=1; done < <(pvesh get /cluster/ha/resources --output-format json 2>/dev/null \
       | tr '{},' '\n' | grep '"sid"' | awk -F'"' '{print $4}')
  fi
fi

# ---------- helpers ----------
conf_get() { # $1=confpath $2=key (e.g., name|hostname|onboot|cores|sockets|memory)
  local f="$1" k="$2"
  [ -r "$f" ] || { echo ""; return; }
  awk -F': ' -v key="$k" '$1==key{print $2; exit}' "$f"
}
name_from_conf(){
  local typ="$1" vmid="$2"
  if [ "$typ" = "qemu" ]; then conf="/etc/pve/qemu-server/${vmid}.conf"; conf_get "$conf" "name"
  else conf="/etc/pve/lxc/${vmid}.conf"; conf_get "$conf" "hostname"; fi
}
onboot_from_conf(){
  local typ="$1" vmid="$2"
  if [ "$typ" = "qemu" ]; then conf="/etc/pve/qemu-server/${vmid}.conf"
  else conf="/etc/pve/lxc/${vmid}.conf"; fi
  conf_get "$conf" "onboot"
}

# ---------- get cluster resources (VMs only) ----------
# Fields we want (per item): vmid,type,node,name,status,maxmem,uptime
get_resources_json(){ pvesh get /cluster/resources --type vm --output-format json; }

# Collect into a tabular stream: node|type|vmid|name|status|onboot|ha
emit_lines(){
  if have jq; then
    get_resources_json | jq -r '
      map({
        node, type, vmid, name: (.name // ""), status: (.status // "unknown")
      }) | sort_by(.node, .type, .vmid) |
      .[] | "\(.node)|\(.type)|\(.vmid)|\(.name)|\(.status)"'
  else
    # Fallback: minimal parse for {"node":"n1","type":"qemu","vmid":100,"name":"foo","status":"running"}
    get_resources_json \
      | tr '\n' ' ' \
      | sed 's/\},{/}\n{/g' \
      | sed -n 's/.*"node":"\([^"]*\)".*"type":"\([^"]*\)".*"vmid":\([0-9]\+\).*"name":"\([^"]*\)".*"status":"\([^"]*\)".*/\1|\2|\3|\4|\5/p' \
      | sort
  fi | while IFS='|' read -r node typ vmid name status; do
        # Backfill name if empty
        if [ -z "$name" ] || [ "$name" = "null" ]; then
          name="$(name_from_conf "$typ" "$vmid")"
        fi
        # onboot (from conf)
        ob="$(onboot_from_conf "$typ" "$vmid")"
        [ -z "$ob" ] && ob="0"
        # HA flag
        rid="${typ}:${vmid}"
        ham="no"; [ "${HA[$rid]+x}" ] && ham="yes"
        echo "$node|$typ|$vmid|$name|$status|$ob|$ham"
      done
}

# Group by node, print pretty
current_node=""
count_node=0
total=0

print_header_for_node(){
  local node="$1"
  echo -e "${CYN}${BLD}Node:${RST} ${CYN}$node${RST}"
  printf "  %-4s %-6s %-6s %-4s %-10s %s\n" "Type" "VMID" "OnBoot" "HA" "Status" "Name"
}


status_color(){
  case "$1" in
    running) echo -e "${GRN}running${RST}" ;;
    stopped|stopped\*) echo -e "${RED}stopped${RST}" ;;
    paused) echo -e "${YLW}paused${RST}" ;;
    *) echo -e "${MAG}$1${RST}" ;;
  esac
}

typ_tag(){ [ "$1" = "qemu" ] && echo "VM  " || echo "CT  "; }

emit_lines | while IFS='|' read -r node typ vmid name status onboot ham; do
  if [ "$node" != "$current_node" ]; then
    if [ -n "$current_node" ]; then
      echo -e "  ${DIM}Count:${RST} $count_node\n"
    fi
    current_node="$node"
    count_node=0
    print_header_for_node "$node"
  fi
  count_node=$((count_node+1))
  total=$((total+1))

  ob_disp="$onboot"; [ "$onboot" = "1" ] && ob_disp="${GRN}1${RST}" || ob_disp="${DIM}0${RST}"
  ha_disp="$ham";   [ "$ham" = "yes" ] && ha_disp="${BLU}yes${RST}" || ha_disp="${DIM}no${RST}"
  st_disp="$(status_color "$status")"
  tdisp="$(typ_tag "$typ")"

  printf "  %-4s %-6s %-6b %-4b %-10b %s\n" \
    "$tdisp" "$vmid" "$ob_disp" "$ha_disp" "$st_disp" "${name:-<no-name>}"
done

if [ -n "$current_node" ]; then
  echo -e "  ${DIM}Count:${RST} $count_node\n"
fi

echo -e "${BLU}${BLD}Total guests:${RST} $total"
