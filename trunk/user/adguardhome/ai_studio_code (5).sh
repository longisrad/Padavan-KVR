#!/bin/sh
# AdGuardHome manager for Padavan
# Mode 1: dnsmasq(53) -> AGH(5353)
# Mode 2: AGH(53) -> dnsmasq(5335)

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# NVRAM values from WebUI
ENABLE=$(nvram get adg_enable)
REDIRECT=$(nvram get adg_redirect)

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

# --- Download & Check Binary (Giữ nguyên từ bản gốc chạy tốt của bạn) ---
ensure_binary() {
    if [ -x "$BIN_PATH" ] && [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    log "Binary missing or invalid, downloading..."
    tag="$(curl -sk --connect-timeout 5 "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)"
    [ -z "$tag" ] && tag="v0.107.78"
    url="https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    mkdir -p "$BIN_DIR/_dl"
    curl -Lksfo "$BIN_DIR/_dl/agh.tar.gz" "$url"
    tar -xzf "$BIN_DIR/_dl/agh.tar.gz" -C "$BIN_DIR/_dl"
    mv "$(find "$BIN_DIR/_dl" -type f -name AdGuardHome | head -n1)" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/_dl"
}

# Khôi phục dnsmasq về mặc định
dnsmasq_reset() {
    sed -i '/^no-resolv$/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^server=127.0.0.1#/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
}

# Sửa cổng DNS trong file AdGuardHome.yaml
update_agh_yaml_port() {
    local target_port=$1
    if [ -f "$CFG_PATH" ]; then
        # Tìm chính xác dòng port: nằm trong block dns:
        sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $target_port/" "$CFG_PATH"
        log "AGH config: DNS port changed to $target_port"
    fi
}

start() {
    if [ "$ENABLE" != "1" ]; then
        stop
        return 0
    fi

    ensure_binary
    [ ! -f "$CFG_PATH" ] && log "Warning: Config file not found, AGH will use defaults"

    log "Setting up Network Mode $REDIRECT..."
    
    # BƯỚC 1: Dọn dẹp dnsmasq và xác định cổng cho AGH
    dnsmasq_reset
    
    if [ "$REDIRECT" = "1" ]; then
        # MODE 1: dnsmasq(53) làm chủ, AGH(5353) làm tớ
        update_agh_yaml_port 5353
        printf 'no-resolv\nserver=127.0.0.1#5353\n' >> /etc/storage/dnsmasq/dnsmasq.conf
        AGH_LISTEN_PORT=5353
    elif [ "$REDIRECT" = "2" ]; then
        # MODE 2: AGH(53) làm chủ, dnsmasq(5335) làm tớ
        update_agh_yaml_port 53
        printf 'port=5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
        AGH_LISTEN_PORT=53
    else
        # MODE 0: Chỉ chạy AGH ở cổng mặc định 5353, dnsmasq không đổi
        update_agh_yaml_port 5353
        AGH_LISTEN_PORT=5353
    fi

    # BƯỚC 2: Khởi động lại dnsmasq để nhả cổng
    /sbin/restart_dhcpd
    log "Waiting for dnsmasq to release ports..."
    sleep 3

    # BƯỚC 3: Kiểm tra xem có ai còn chiếm cổng AGH định dùng không
    if netstat -ulnp | grep -q ":$AGH_LISTEN_PORT "; then
        log "ERROR: Port $AGH_LISTEN_PORT is still busy! AGH might fail."
    fi

    # BƯỚC 4: Khởi chạy AGH
    log "Starting AdGuardHome process..."
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "AGH started successfully (PID: $(pidof AdGuardHome))"
        # Watchdog
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "ERROR: AdGuardHome failed to start. Reverting DNS..."
        dnsmasq_reset
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Stopping AdGuardHome..."
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE" 2>/dev/null
    killall -9 AdGuardHome 2>/dev/null
    dnsmasq_reset
    /sbin/restart_dhcpd
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 2; start ;;
    status)  is_running && echo "running" || echo "stopped" ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac