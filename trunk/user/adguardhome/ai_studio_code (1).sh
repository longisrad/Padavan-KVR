#!/bin/sh
# AdGuardHome manager for Padavan WebUI integration
# Port mapping:
# Mode 0 (None): dnsmasq default (53), AGH stopped or bypass
# Mode 1: dnsmasq (53) -> AGH (5353)
# Mode 2: AGH (53) -> dnsmasq (5335)

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# Lấy chế độ từ NVRAM (đã chọn từ WebUI)
ADG_MODE="$(nvram get adg_redirect)"
[ -z "$ADG_MODE" ] && ADG_MODE=0

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

# Hàm cập nhật cổng DNS trực tiếp vào file cấu hình YAML của AGH
update_agh_port() {
    local target_port=$1
    if [ -f "$CFG_PATH" ]; then
        # Tìm dòng 'port:' trong phần 'dns:' và thay đổi giá trị
        sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $target_port/" "$CFG_PATH"
        log "AGH config: DNS port set to $target_port"
    fi
}

# Khôi phục dnsmasq về mặc định (Cổng 53, không chuyển tiếp)
dnsmasq_reset() {
    sed -i '/^no-resolv$/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^server=127.0.0.1#/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    log "dnsmasq: Reset to default (Port 53)"
}

# Cấu hình DNS cho từng Mode
apply_network_logic() {
    case "$ADG_MODE" in
        1)
            # Mode 1: dnsmasq 53 -> AGH 5353
            dnsmasq_reset
            update_agh_port 5353
            printf 'no-resolv\nserver=127.0.0.1#5353\n' >> /etc/storage/dnsmasq/dnsmasq.conf
            log "Network Mode 1: dnsmasq(53) forwards to AGH(5353)"
            ;;
        2)
            # Mode 2: AGH 53 -> dnsmasq 5335
            dnsmasq_reset
            update_agh_port 53
            printf 'port=5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
            log "Network Mode 2: AGH(53) is primary, dnsmasq moved to 5335"
            ;;
        *)
            # Mode 0 hoặc khác: Tắt AGH, dnsmasq về 53
            dnsmasq_reset
            log "Network Mode 0: AdGuardHome disabled"
            ;;
    esac
    # Áp dụng cấu hình dnsmasq mới
    /sbin/restart_dhcpd
}

ensure_binary() {
    if [ -x "$BIN_PATH" ]; then return 0; fi
    log "Downloading AdGuardHome binary..."
    # Tải bản mipsle cho Newifi3/Padavan
    url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    mkdir -p "$BIN_DIR"
    curl -Lksfo "$BIN_DIR/agh.tar.gz" "$url"
    tar -xzf "$BIN_DIR/agh.tar.gz" -C "$BIN_DIR"
    mv "$BIN_DIR/AdGuardHome/AdGuardHome" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/agh.tar.gz" "$BIN_DIR/AdGuardHome"
}

start() {
    if [ "$ADG_MODE" = "0" ]; then
        stop
        return 0
    fi

    log "Starting with Mode $ADG_MODE..."
    ensure_binary

    # Tạo config mặc định nếu chưa có
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
    fi

    # Áp dụng logic cổng trước khi chạy binary
    apply_network_logic

    # Chạy AdGuardHome
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 3
    if is_running; then
        log "AdGuardHome is running (PID: $(pidof AdGuardHome))"
        # Cài watchdog để tự khởi động lại nếu crash
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "ERROR: AdGuardHome failed to start"
        dnsmasq_reset
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Stopping AdGuardHome..."
    # Xóa watchdog
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE" 2>/dev/null
    
    # Giết tiến trình
    killall -9 AdGuardHome 2>/dev/null
    
    # Khôi phục mạng về mặc định
    dnsmasq_reset
    /sbin/restart_dhcpd
    log "Stopped. DNS reverted to dnsmasq default."
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 2; start ;;
    status)  is_running && echo "running" || echo "stopped" ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac