#!/bin/sh
# ==================== gen_links.sh (All Inbounds + Auto IP) ====================

WORKDIR="/opt/tmp_sb_ext/sing-box-1.13.12-extended-2.4.1-linux-mipsle"
CONF="$WORKDIR/conf2_final.json"
OUT_FILE="$WORKDIR/clients.txt"

# 1. Автоматическое определение локального IP адреса роутера
SERVER_IP=$(nvram get lan_ipaddr 2>/dev/null)
if [ -z "$SERVER_IP" ]; then
    # Фолбэк 1: Чтение IP адреса с сетевого интерфейса локальной сети (br0)
    SERVER_IP=$(ip addr show br0 2>/dev/null | grep -w inet | awk '{print $2}' | cut -d/ -f1)
fi
if [ -z "$SERVER_IP" ]; then
    # Фолбэк 2: Если команды не сработали, ставим классический дефолт
    SERVER_IP="192.168.1.1" 
fi

echo -e "\033[1;36mDetected Router LAN IP:\033[0m $SERVER_IP"
echo "Generating links... → $OUT_FILE"
echo "" > "$OUT_FILE"

b64enc() {
    echo -n "$1" | openssl base64 -A 2>/dev/null | tr -d '\n\r'
}

# --- 1. Mixed и HTTP ---
echo -e "\033[1;34m--- HTTP / Mixed Proxy ---\033[0m"
jq -c '.inbounds[] | select(.type=="mixed" or .type=="http")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    TYPE=$(echo "$line" | jq -r '.type')
    LINK="http://$SERVER_IP:$PORT#$TAG"
    echo "$LINK" | tee -a "$OUT_FILE"
done

# --- 2. SOCKS5 ---
echo -e "\033[1;34m--- SOCKS5 ---\033[0m"
jq -c '.inbounds[] | select(.type=="socks" and .tag!="socks-test")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    LINK="socks5://$SERVER_IP:$PORT#$TAG"
    echo "$LINK" | tee -a "$OUT_FILE"
done

# --- 3. Shadowsocks ---
echo -e "\033[1;34m--- Shadowsocks ---\033[0m"
jq -c '.inbounds[] | select(.type=="shadowsocks")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    METHOD=$(echo "$line" | jq -r '.method')
    PASS=$(echo "$line" | jq -r '.password')
    AUTH=$(b64enc "$METHOD:$PASS")
    LINK="ss://$AUTH@$SERVER_IP:$PORT#$TAG"
    echo "$LINK" | tee -a "$OUT_FILE"
done

# --- 4. Hysteria 2 ---
echo -e "\033[1;34m--- Hysteria 2 ---\033[0m"
jq -c '.inbounds[] | select(.type=="hysteria2")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password // .password')
    LINK="hy2://$PASS@$SERVER_IP:$PORT?insecure=1#$TAG"
    echo "$LINK" | tee -a "$OUT_FILE"
done

# --- 5. VLESS (Если поднят как входящий) ---
jq -c '.inbounds[] | select(.type=="vless")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    UUID=$(echo "$line" | jq -r '.users[0].uuid // .uuid')
    LINK="vless://$UUID@$SERVER_IP:$PORT?encryption=none&security=none&type=tcp#$TAG"
    echo -e "\033[1;34m--- VLESS ---\033[0m"
    echo "$LINK" | tee -a "$OUT_FILE"
done

# --- 6. Trojan (Если поднят как входящий) ---
jq -c '.inbounds[] | select(.type=="trojan")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password // .password')
    LINK="trojan://$PASS@$SERVER_IP:$PORT?security=none#$TAG"
    echo -e "\033[1;34m--- Trojan ---\033[0m"
    echo "$LINK" | tee -a "$OUT_FILE"
done

echo -e "\n\033[1;32mDONE! All links saved to $OUT_FILE\033[0m"