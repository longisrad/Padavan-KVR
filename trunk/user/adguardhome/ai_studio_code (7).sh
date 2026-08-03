#!/bin/sh
# AdGuardHome manager for Padavan WebUI
# Mode 1: dnsmasq (53) -> AdGuardHome (5335)
# Mode 2: AdGuardHome (53) -> dnsmasq (5335)

BIN_PATH="/usr/bin/AdGuardHome" # Giả định bạn để binary trong /usr/bin khi build firmware
[ ! -f "$BIN_PATH" ] && BIN_PATH="/tmp/AdGuardHome/AdGuardHome"

CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# Lấy thông số từ WebUI (NVRAM)
ADG_ENABLE=$(nvram get adg_enable)
ADG_MODE=$(nvram get adg_redirect)

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

# --- Download binary nếu chưa có (phòng trường hợp build script tải về /tmp) ---
ensure_binary() {
    [ -f "$BIN_PATH" ] && return 0
    log "Binary not found at $BIN_PATH, downloading..."
    mkdir -p "/tmp/AdGuardHome"
    url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    curl -Lksfo "/tmp/agh.tar.gz" "$url"
    tar -xzf "/tmp/agh.tar.gz" -C "/tmp/AdGuardHome"
    mv /tmp/AdGuardHome/AdGuardHome/AdGuardHome "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "/tmp/agh.tar.gz"
}

# --- Cấu hình dnsmasq theo Mode ---
dnsmasq_sync() {
    # Xóa các cấu hình cũ liên quan đến AGH
    sed -i '/^no-resolv$/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^server=127.0.0.1#/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf

    if [ "$ADG_MODE" = "1" ]; then
        log "Mode 1: dnsmasq(53) -> AGH(5335)"
        printf 'no-resolv\nserver=127.0.0.1#5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    elif [ "$ADG_MODE" = "2" ]; then
        log "Mode 2: AGH(53) -> dnsmasq(5335)"
        printf 'port=5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    fi
    
    /sbin/restart_dhcpd
}

# --- Đảm bảo file YAML khớp với Mode đã chọn trên WebUI ---
yaml_sync_port() {
    [ ! -f "$CFG_PATH" ] && return
    if [ "$ADG_MODE" = "2" ]; then
        sed -i "/dns:/,/port:/ s/port: [0-9]*/port: 53/" "$CFG_PATH"
    else
        sed -i "/dns:/,/port:/ s/port: [0-9]*/port: 5335/" "$CFG_PATH"
    fi
    log "YAML DNS port synced with Mode $ADG_MODE"
}

start() {
    if [ "$ADG_ENABLE" != "1" ]; then
        stop
        return 0
    fi

    ensure_binary
    mkdir -p "$CFG_DIR"

    # Nếu đã có file config, đồng bộ cổng DNS trước khi chạy
    if [ -f "$CFG_PATH" ]; then
        yaml_sync_port
    else
        log "No config found. Setup Wizard will be available on port 3000."
    fi

    # Xử lý dnsmasq: Nếu là Mode 2, phải giết dnsmasq trước để AGH chiếm cổng 53
    [ "$ADG_MODE" = "2" ] && killall dnsmasq 2>/dev/null
    dnsmasq_sync
    sleep 2

    # Chạy AdGuard Home
    log "Starting AdGuard Home binary..."
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "AdGuard Home is running."
        # Watchdog
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "Error: AdGuard Home failed to start. Port conflict?"
        # Fallback dnsmasq về mặc định để không mất mạng
        sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Stopping AdGuard Home..."
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE" 2>/dev/null
    killall -9 AdGuardHome 2>/dev/null
    
    # Trả dnsmasq về mặc định
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    status) is_running && echo "running" || echo "stopped" ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac