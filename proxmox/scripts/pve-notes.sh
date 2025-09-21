#!/usr/bin/env bash
# pve-notes-export-min.sh
# Export URL-encoded header notes (top '#' comments) and/or 'description:' notes
# from ALL VMs/CTs into one Markdown. 

set -euo pipefail

# save to given file, or ./proxmox-notes.md
OUT="${1:-./proxmox-notes.md}"

# enumerate confs cluster-wide
mapfile -t FILES < <(find /etc/pve/nodes -type f \( -path "*/qemu-server/*.conf" -o -path "*/lxc/*.conf" \) -print 2>/dev/null | sort -V)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No VM/CT confs under /etc/pve/nodes/* — run on a Proxmox node." >&2
  exit 1
fi

# helper: derive node/type/id/title
node_of() { sed -n 's#^/etc/pve/nodes/\([^/]*\)/.*#\1#p' <<<"$1"; }
type_of() { [[ "$1" == *"/qemu-server/"* ]] && echo "VM" || echo "CT"; }
id_of()   { basename "$1" .conf; }
title_of(){
  # prefer name:/hostname: from file
  local t
  t=$(awk '/^name:/{sub(/^name:[[:space:]]*/,"");print;exit} /^hostname:/{sub(/^hostname:[[:space:]]*/,"");print;exit}' "$1")
  [[ -n "$t" ]] && echo "$t" || echo "(no name)"
}

# start doc
{
  echo "# Proxmox Notes Export"
  echo "_Generated: $(date '+%Y-%m-%d %H:%M')_"
  echo

  # group by node
  declare -A NODES
  for f in "${FILES[@]}"; do NODES["$(node_of "$f")"]=1; done

  for NODE in $(printf "%s\n" "${!NODES[@]}" | sort); do
    echo "## Node: \`$NODE\`"
    echo

    # node’s files: VMs first, then CTs, numeric sort by ID
    mapfile -t NODE_FILES < <(
      printf "%s\n" "${FILES[@]}" \
      | awk -v n="$NODE" '
          function id(p){ sub(/^.*\//,"",p); sub(/\.conf$/,"",p); return p+0 }
          index($0,"/nodes/" n "/") {
            t = (index($0,"/qemu-server/")>0)?0:1
            printf("%d %010d %s\n", t, id($0), $0)
          }' \
      | sort -n | cut -d' ' -f3-
    )

    for CONF in "${NODE_FILES[@]}"; do
      [[ -e "$CONF" ]] || continue
      TYPE="$(type_of "$CONF")"
      ID="$(id_of "$CONF")"
      TITLE="$(title_of "$CONF")"

      # progress to stderr
      echo "→ ${NODE}: ${TYPE} ${ID}  ($CONF)" >&2

      # === THIS IS THE EXACT ONE-LINER YOU VERIFIED ===
      HEADER=$(
        awk '/^#/ { sub(/^#[[:space:]]?/,""); print; next } { exit }' "$CONF" \
        | python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read()), end="")' \
        || true
      )

      # fallback: description: single-line or YAML block
      if [[ -z "$HEADER" ]]; then
        DESC=$(
          awk '
            BEGIN { in_desc=0; out=""; have=0 }
            /^description:/ {
              val=substr($0,13); sub(/^[ \t]+/,"",val)
              if (val ~ /^\|/) { in_desc=1; next }
              out=val; gsub(/\\n/,"\n",out); have=1; next
            }
            in_desc && /^[ \t]/ {
              line=$0
              if (substr(line,1,1)==" ") line=substr(line,2); else sub(/^\t+/,"",line)
              out = have ? out "\n" line : line; have=1; next
            }
            in_desc && !/^[ \t]/ { in_desc=0 }
            END { gsub(/\r/,"",out); if (have) print out }
          ' "$CONF" || true
        )
      else
        DESC="$HEADER"
      fi

      echo "### $TYPE $ID — $TITLE"
      echo "*Node:* \`$NODE\`  ·  *Type:* \`$TYPE\`  ·  *Config:* \`$CONF\`"
      echo
      if [[ -n "$DESC" ]]; then
        echo '```markdown'
        printf "%s\n" "$DESC"
        echo '```'
      else
        echo "_No notes/description set._"
      fi
      echo
    done
  done
} > "$OUT"

echo "✅ Saved Markdown export to: $OUT"