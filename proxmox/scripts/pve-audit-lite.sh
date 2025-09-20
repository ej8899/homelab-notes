#!/usr/bin/env bash
# pve-audit-lite.sh — Plain-text, aligned & colorized VM/CT audit for a Proxmox cluster
# - Run on any PVE node (needs pvesh and /etc/pve mounted)
# - No files; stdout only
# - Works even if some nodes are offline (reads pmxcfs + cluster resources)

set -euo pipefail

# ----- colors (disabled if not a TTY) -----
if [ -t 1 ]; then
  RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; CYN=$'\e[36m'; BLD=$'\e[1m'; DIM=$'\e[2m'; RST=$'\e[0m'
else
  RED=""; GRN=""; YLW=""; BLU=""; CYN=""; BLD=""; DIM=""; RST=""
fi

die(){ echo -e "${RED}ERROR:${RST} $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

[ -x /usr/bin/pvesh ] || die "pvesh not found (run on a Proxmox node)."
[ -d /etc/pve ] || die "/etc/pve not mounted; pmxcfs unavailable."
have column || die "'column' not found (install util-linux)."

ts="$(date +'%F %T')"
echo -e "${CYN}${BLD}Proxmox Cluster Audit${RST} ${DIM}[$ts]${RST}\n"

# ----- HA map (vm:100 / ct:101) -----
declare -A HA
if pvesh get /cluster/ha/resources --output-format json >/dev/null 2>&1; then
  if have jq; then
    while read -r sid; do HA["$sid"]=1; done < <(pvesh get /cluster/ha/resources --output-format json | jq -r '.[].sid')
  else
    while read -r sid; do HA["$sid"]=1; done < <(pvesh get /cluster/ha/resources --output-format json 2>/dev/null \
      | tr '{},' '\n' | grep '"sid"' | awk -F'"' '{print $4}')
  fi
fi

# ----- helpers -----
conf_get(){ local f="$1" k="$2"; [ -r "$f" ] || { echo ""; return; }; awk -F': ' -v key="$k" '$1==key{print $2; exit}' "$f"; }
name_from_conf(){
  local typ="$1" vmid="$2"
  if [ "$typ" = "qemu" ]; then conf="/etc/pve/qemu-server/${vmid}.conf"; conf_get "$conf" "name"
  else conf="/etc/pve/lxc/${vmid}.conf"; conf_get "$conf" "hostname"; fi
}
get_resources_json(){ pvesh get /cluster/resources --type vm --output-format json; }

emit_lines(){ # node|type|vmid|name|status|onboot|ha
  if have jq; then
    get_resources_json | jq -r '
      map({node, type, vmid, name: (.name // ""), status: (.status // "unknown")})
      | sort_by(.node, .type, .vmid)
      | .[] | "\(.node)|\(.type)|\(.vmid)|\(.name)|\(.status)"'
  else
    get_resources_json | tr '\n' ' ' | sed 's/\},{/}\n{/g' \
      | sed -n 's/.*"node":"\([^"]*\)".*"type":"\([^"]*\)".*"vmid":\([0-9]\+\).*"name":"\([^"]*\)".*"status":"\([^"]*\)".*/\1|\2|\3|\4|\5/p' \
      | sort
  fi | while IFS='|' read -r node typ vmid name status; do
        [ -z "$name" ] || [ "$name" = "null" ] || true
        if [ -z "$name" ] || [ "$name" = "null" ]; then name="$(name_from_conf "$typ" "$vmid")"; fi
        onboot="0"
        if [ "$typ" = "qemu" ]; then conf="/etc/pve/qemu-server/${vmid}.conf"; else conf="/etc/pve/lxc/${vmid}.conf"; fi
        vob="$(conf_get "$conf" "onboot")"; [ -n "$vob" ] && onboot="$vob"
        rid="${typ}:${vmid}"; ham="no"; [ "${HA[$rid]+x}" ] && ham="yes"
        echo "$node|$typ|$vmid|$name|$status|$onboot|$ham"
      done
}

# ----- printing (align first, then color) -----
print_table(){
  # $1 buffer with header + rows, TAB-separated
  local aligned out
  aligned="$(echo -e "$1" | column -t -s $'\t')"
  # Colorize after alignment so spacing stays perfect
  out="$(sed -E \
    -e '1s/.*/'"$CYN$BLD"'&'"$RST"'/g' \
    -e 's/\brunning\b/'"$GRN"'&'"$RST"'/g' \
    -e 's/\bstopped\*?\b/'"$RED"'&'"$RST"'/g' \
    -e 's/\bpaused\b/'"$YLW"'&'"$RST"'/g' \
    -e 's/\byes\b/'"$BLU"'&'"$RST"'/g' \
    -e 's/\bno\b/'"$DIM"'&'"$RST"'/g' \
    -e 's/\b1\b/'"$GRN"'&'"$RST"'/g' \
    -e 's/\b0\b/'"$DIM"'&'"$RST"'/g' \
  <<< "$aligned")"
  echo -e "$out"
}

current_node=""
count_node=0
total=0
buf_header=$'Type\tVMID\tOnBoot\tHA\tStatus\tName'
buf=""

flush_node(){
  [ -z "$current_node" ] && return
  echo -e "${CYN}${BLD}Node:${RST} ${CYN}$current_node${RST}"
  print_table "$buf"
  echo -e "  ${DIM}Count:${RST} $count_node\n"
}

# Build per-node buffers (no subshell so variables persist)
while IFS='|' read -r node typ vmid name status onboot ham; do
  if [ "$node" != "$current_node" ]; then
    flush_node
    current_node="$node"
    count_node=0
    buf="$buf_header"$'\n'
  fi
  count_node=$((count_node+1))
  total=$((total+1))
  [ "$typ" = "qemu" ] && tdisp="VM" || tdisp="CT"
  # Tab-separated fields; names with spaces are fine
  buf+="$tdisp"$'\t'"$vmid"$'\t'"$onboot"$'\t'"$ham"$'\t'"$status"$'\t'"${name:-<no-name>}"$'\n'
done < <(emit_lines)

flush_node
echo -e "${CYN}${BLD}Total guests:${RST} $total"
