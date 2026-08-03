#!/bin/sh
# AdGuardHome manager for Padavan - Fixed Logic
# Mode 1: dnsmasq(53) -> AGH(5353)
# Mode 2: AGH(53) -> dnsmasq(5335)

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# Lấy cấu hình từ NVRAM
ENABLE=$(nvram get adg_enable)
REDIRECT=$(nvram get adg_redirect)

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

# --- Giữ nguyên logic download/check binary của bạn ---
fetch_latest_tag() {
    tag="$(curl -sk --connect-timeout 5 "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)"
    [ -z "$tag" ] && tag="v0.107.78"
    echo "$tag"
}

download_binary() {
    tag="$(fetch_latest_tag)"
    log "Downloading AdGuardHome ${tag}..."
    mkdir -p "$BIN_DIR"
    rm -rf "$BIN_DIR/_dl" && mkdir -p "$BIN_DIR/_dl"
    url="https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    archive="$BIN_DIR/_dl/agh.tar.gz"

    curl -Lksfo "$archive" --connect-timeout 10 --retry 2 "$url" || wget -q -O "$archive" "$url"
    
    tar -xzf "$archive" -C "$BIN_DIR/_dl" 2>/dev/null
    extracted="$(find "$BIN_DIR/_dl" -type f -name AdGuardHome | head -n1)"
    if [ -z "$extracted" ]; then return 1; fi

    mv "$extracted" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/_dl"
    return 0
}

ensure_binary() {
    if [ -x "$BIN_PATH" ] && [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    download_binary
}
# -------------------------------------------------------

# Hàm reset dnsmasq
dnsmasq_reset() {
    sed -i '/^no-resolv$/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^server=127.0.0.1#/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
}

# Hàm update port vào YAML (dùng sed chính xác hơn)
update_yaml_port() {
    local p=$1
    if [ -f "$CFG_PATH" ]; then
        # Sửa port trong block dns:
        sed -i "/^dns:/,/  port:/ s/  port: [0-9]*/  port: $p/" "$CFG_PATH"
    fi
}

start() {
    if [ "$ENABLE" != "1" ]; then
        stop
        return 0
    fi

    log "Starting AdGuardHome (Mode $REDIRECT)..."
    
    if ! ensure_binary; then
        log "Error: Binary not found or incompatible!"
        return 1
    fi

    # 1. Xử lý Logic mạng TRƯỚC khi khởi động AGH
    dnsmasq_reset
    if [ "$REDIRECT" = "1" ]; then
        # Mode 1: dnsmasq(53) -> AGH(5353)
        update_yaml_port 5353
        printf 'no-resolv\nserver=127.0.0.1#5353\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    elif [ "$REDIRECT" = "2" ]; then
        # Mode 2: AGH(53) -> dnsmasq(5335)
        update_yaml_port 53
        printf 'port=5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    fi
    
    # Quan trọng: Restart dnsmasq để nhả cổng 53
    /sbin/restart_dhcpd
    sleep 2 # Chờ dnsmasq nhả cổng

    # 2. Tạo config mặc định nếu chưa có
    if [ ! -s "$CFG_PATH" ]; then
        mkdir -p "$CFG_DIR"
        cat > "$CFG_PATH" <<EOF
http:
  address: 0.0.0.0:3030
users:
  - name: admin
    password: \$2b\$12\$zgC5mg2IyANRLOi8OHgVvePjzQ0s6uIgjlG1P3.nnzQ3ACXD9czYC
dns:
  bind_hosts:
    - 0.0.0.0
  port: 5353
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - [/lan/]127.0.0.1:5335
EOF
        # Nếu là Mode 2 ngay từ đầu thì sửa luôn port
        [ "$REDIRECT" = "2" ] && update_yaml_port 53
    fi

    # 3. Chạy AGH
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "Running (PID: $(pidof AdGuardHome))"
        # Watchdog
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "CRITICAL: AGH failed to bind port. Check if Port 53 is still used."
        # Fallback về dnsmasq mặc định để không mất mạng
        dnsmasq_reset
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Stopping..."
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE" 2>/dev/null
    killall -9 AdGuardHome 2>/dev/null
    dnsmasq_reset
    /sbin/restart_dhcpd
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    status) is_running && echo "running" || echo "stopped" ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac