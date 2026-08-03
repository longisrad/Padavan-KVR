#!/bin/sh
# AdGuardHome manager for Padavan - Integrated with WebUI
# Biến NVRAM: adg_enable (0/1), adg_redirect (0/1/2)

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# Đọc cấu hình từ NVRAM
ENABLE=$(nvram get adg_enable)
REDIRECT=$(nvram get adg_redirect)

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

# Hàm cập nhật cổng DNS vào file YAML
update_agh_port() {
    local port=$1
    if [ -f "$CFG_PATH" ]; then
        # Tìm dòng port: bên dưới dns: và thay đổi
        sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $port/" "$CFG_PATH"
        log "AGH: Set DNS port to $port"
    fi
}

# Khôi phục dnsmasq về nguyên bản
dnsmasq_reset() {
    sed -i '/^no-resolv$/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^server=127.0.0.1#/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    log "dnsmasq: Config reset to default"
}

apply_network_logic() {
    case "$REDIRECT" in
        1)
            # Mode 1: dnsmasq (53) -> AGH (5353)
            dnsmasq_reset
            update_agh_port 5353
            printf 'no-resolv\nserver=127.0.0.1#5353\n' >> /etc/storage/dnsmasq/dnsmasq.conf
            log "Logic: Mode 1 - dnsmasq(53) forwards to AGH(5353)"
            ;;
        2)
            # Mode 2: AGH (53) -> dnsmasq (5335)
            # Bước này quan trọng: phải nhả cổng 53 của dnsmasq trước
            dnsmasq_reset
            update_agh_port 53
            printf 'port=5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
            log "Logic: Mode 2 - AGH(53) direct, dnsmasq moved to 5335"
            ;;
        *)
            # Mode 0: Không điều hướng
            dnsmasq_reset
            log "Logic: Mode None - dnsmasq handles all"
            ;;
    esac
    /sbin/restart_dhcpd
}

ensure_binary() {
    if [ -x "$BIN_PATH" ]; then return 0; fi
    log "Downloading AdGuardHome binary (mipsle)..."
    url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    mkdir -p "$BIN_DIR"
    curl -Lksfo "$BIN_DIR/agh.tar.gz" "$url"
    tar -xzf "$BIN_DIR/agh.tar.gz" -C "$BIN_DIR"
    mv "$BIN_DIR/AdGuardHome/AdGuardHome" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/agh.tar.gz" "$BIN_DIR/AdGuardHome"
}

start() {
    if [ "$ENABLE" != "1" ]; then
        log "AdGuardHome is disabled in WebUI"
        stop
        return 0
    fi

    ensure_binary

    if [ ! -s "$CFG_PATH" ]; then
        mkdir -p "$CFG_DIR"
        # Tạo config mặc định hỗ trợ LAN và Tailscale
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
    - [/ts.net/]100.100.100.100
EOF
    fi

    # Áp dụng logic mạng
    apply_network_logic

    # Khởi chạy AGH
    log "Launching AdGuardHome process..."
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 3
    if is_running; then
        log "AdGuardHome started (PID: $(pidof AdGuardHome))"
        # Watchdog
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "Error: AdGuardHome could not start. Reverting DNS..."
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