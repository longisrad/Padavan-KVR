#!/bin/sh
# AdGuardHome manager for Padavan - Web UI port 3000
BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"

ENABLE=$(nvram get adg_enable)
REDIRECT=$(nvram get adg_redirect)

log() { logger -t "$LOG_TAG" "$1"; }
is_running() { [ -n "$(pidof AdGuardHome)" ]; }

# Hàm đưa dnsmasq về nguyên bản
dnsmasq_reset() {
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
}

# Tạo file cấu hình và bỏ qua bước cài đặt (Web Port 3000)
generate_config() {
    local dns_p=$1
    mkdir -p "$CFG_DIR"
    cat > "$CFG_PATH" <<EOF
http:
  address: 0.0.0.0:3000
  session_ttl: 720h
dns:
  bind_hosts:
    - 0.0.0.0
  port: $dns_p
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - [/lan/]127.0.0.1:5335
    - [/ts.net/]100.100.100.100
users:
  - name: admin
    password: \$2b\$12\$zgC5mg2IyANRLOi8OHgVvePjzQ0s6uIgjlG1P3.nnzQ3ACXD9czYC
schema_version: 28
EOF
}

start() {
    [ "$ENABLE" != "1" ] && { stop; return 0; }

    log "Starting AdGuardHome Mode $REDIRECT..."

    # 1. Xử lý Logic Port & dnsmasq
    dnsmasq_reset
    local agh_dns_port=5353
    
    if [ "$REDIRECT" = "2" ]; then
        # Mode 2: AGH chiếm cổng 53
        agh_dns_port=53
        echo "port=5335" >> /etc/storage/dnsmasq/dnsmasq.conf
        log "Mode 2: Killing dnsmasq to release port 53..."
        killall dnsmasq 2>/dev/null
    else
        # Mode 1: dnsmasq giữ cổng 53, chuyển tiếp cho AGH 5353
        agh_dns_port=5353
        printf 'no-resolv\nserver=127.0.0.1#5353\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    fi

    # Khởi động lại dnsmasq để áp dụng cổng mới (hoặc nhả cổng 53)
    /sbin/restart_dhcpd
    sleep 3 

    # 2. Đảm bảo cổng 53 thật sự trống nếu dùng Mode 2
    if [ "$REDIRECT" = "2" ]; then
        if netstat -ulnp | grep -q ":53 "; then
            log "Port 53 is still busy, forcing kill dnsmasq again..."
            killall -9 dnsmasq 2>/dev/null
            sleep 2
        fi
    fi

    # 3. Luôn tạo/cập nhật config để đảm bảo đúng Port và bypass Setup Wizard
    generate_config $agh_dns_port

    # 4. Chạy AGH
    chmod +x "$BIN_PATH"
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "AGH started! Web UI: http://$(nvram get lan_ipaddr):3000"
        log "User: admin | Pass: admin"
    else
        log "ERROR: AGH failed to start. Port 53 conflict?"
        dnsmasq_reset
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    dnsmasq_reset
    /sbin/restart_dhcpd
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    status) is_running && echo "running" || echo "stopped" ;;
esac