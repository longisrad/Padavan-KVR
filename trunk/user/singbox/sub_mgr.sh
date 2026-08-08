#!/bin/sh
# /etc_ro/singbox/sub_mgr.sh - Helper script xử lý đĩa /etc/storage/singbox_sub.json

FILE="/etc/storage/singbox_sub.json"
JQ_BIN="/tmp/sing-box/jq"

[ ! -f "$JQ_BIN" ] && JQ_BIN="$(command -v jq 2>/dev/null)"
[ ! -f "$FILE" ] && echo "[]" > "$FILE"

case "$1" in
    add)
        name="$2"
        url="$3"
        [ -z "$url" ] && exit 1
        [ -z "$name" ] && name="Group"
        
        if [ -x "$JQ_BIN" ]; then
            "$JQ_BIN" --arg n "$name" --arg u "$url" '. + [{"enabled": true, "name": $n, "url": $u}]' "$FILE" > "${FILE}.tmp" && mv -f "${FILE}.tmp" "$FILE"
        fi
        ;;
    del)
        idx="$2"
        [ -z "$idx" ] && exit 1
        if [ -x "$JQ_BIN" ]; then
            "$JQ_BIN" "del(.[$idx])" "$FILE" > "${FILE}.tmp" && mv -f "${FILE}.tmp" "$FILE"
        fi
        ;;
    toggle)
        idx="$2"
        [ -z "$idx" ] && idx=0
        if [ -x "$JQ_BIN" ]; then
            "$JQ_BIN" ".[$idx].enabled = (.[$idx].enabled == false | not)" "$FILE" > "${FILE}.tmp" && mv -f "${FILE}.tmp" "$FILE"
        fi
        ;;
    preset)
        cat > "$FILE" <<-EOF
[
  {"enabled": true, "name": "🇻🇳 WhiteDNS Base64", "url": "https://sub.whitedns.one/sub/base64.txt"},
  {"enabled": true, "name": "🌐 OpenRay Proxy", "url": "https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/all_valid_proxies.txt"},
  {"enabled": true, "name": "🚀 SoliSpirit SS", "url": "https://raw.githubusercontent.com/SoliSpirit/v2ray-configs/refs/heads/main/Protocols/ss.txt"}
]
EOF
        ;;
esac
