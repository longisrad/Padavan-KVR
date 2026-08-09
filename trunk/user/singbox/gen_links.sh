#!/bin/sh
# ==================== gen_links.sh (Padavan Compatible) ====================

CONF=""
for p in "/tmp/singbox/config.json" "/etc/storage/singbox/config.json" "/etc/storage/scripts/singbox.conf" "/etc/storage/singbox.conf" "/tmp/sing-box/work/config.json"; do
    if [ -f "$p" ]; then
        CONF="$p"
        break
    fi
done

OUT_FILE="/tmp/singbox_clients.txt"
JQ_BIN="/usr/bin/jq"

# Tự động lấy IP LAN Router Padavan
SERVER_IP=$(nvram get lan_ipaddr 2>/dev/null)
[ -z "$SERVER_IP" ] && SERVER_IP="192.168.2.1"

echo "=== SING-BOX CLIENT LINKS (IP Router: $SERVER_IP) ===" > "$OUT_FILE"
echo "" >> "$OUT_FILE"

b64enc() {
    echo -n "$1" | openssl base64 -A 2>/dev/null | tr -d '\n\r'
}

if [ -z "$CONF" ] || [ ! -x "$JQ_BIN" ]; then
    echo "Lỗi: Không tìm thấy file cấu hình Sing-box hoặc không tìm thấy binary jq!" >> "$OUT_FILE"
    exit 1
fi

# --- 1. HTTP / Mixed Proxy ---
echo "--- HTTP / Mixed Proxy ---" >> "$OUT_FILE"
"$JQ_BIN" -c '.inbounds[]? | select(.type=="mixed" or .type=="http")' "$CONF" 2>/dev/null | while read -r line; do
    TAG=$(echo "$line" | "$JQ_BIN" -r '.tag // "mixed"')
    PORT=$(echo "$line" | "$JQ_BIN" -r '.listen_port // 7890')
    echo "http://$SERVER_IP:$PORT#$TAG" >> "$OUT_FILE"
done
echo "" >> "$OUT_FILE"

# --- 2. SOCKS5 ---
echo "--- SOCKS5 Proxy ---" >> "$OUT_FILE"
"$JQ_BIN" -c '.inbounds[]? | select(.type=="socks" and .tag!="socks-test")' "$CONF" 2>/dev/null | while read -r line; do
    TAG=$(echo "$line" | "$JQ_BIN" -r '.tag // "socks"')
    PORT=$(echo "$line" | "$JQ_BIN" -r '.listen_port')
    echo "socks5://$SERVER_IP:$PORT#$TAG" >> "$OUT_FILE"
done
echo "" >> "$OUT_FILE"

# --- 3. Shadowsocks ---
echo "--- Shadowsocks ---" >> "$OUT_FILE"
"$JQ_BIN" -c '.inbounds[]? | select(.type=="shadowsocks")' "$CONF" 2>/dev/null | while read -r line; do
    TAG=$(echo "$line" | "$JQ_BIN" -r '.tag')
    PORT=$(echo "$line" | "$JQ_BIN" -r '.listen_port')
    METHOD=$(echo "$line" | "$JQ_BIN" -r '.method')
    PASS=$(echo "$line" | "$JQ_BIN" -r '.password')
    AUTH=$(b64enc "$METHOD:$PASS")
    echo "ss://$AUTH@$SERVER_IP:$PORT#$TAG" >> "$OUT_FILE"
done

echo "" >> "$OUT_FILE"
echo "=== HOÀN TẤT TẠO LINK CLIENT ===" >> "$OUT_FILE"
