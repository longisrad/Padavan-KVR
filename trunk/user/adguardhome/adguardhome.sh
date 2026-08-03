#!/bin/sh
# AdGuardHome manager for Padavan - Optimized for Newifi3
# Logic: Mode 1 (dnsmasq 53 -> AGH 5335), Mode 2 (AGH 53 -> dnsmasq 5335)

AGH_BIN_SRC="/usr/bin/AdGuardHome"
AGH_TMP="/etc/storage/AdGuardHome"
AGH_CFG="/etc/storage/AdGuardHome/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"

log() { logger -t "$LOG_TAG" "$1"; }

# --- HÀM CẤU HÌNH DNS ---
change_dns() {
    local mode="$(nvram get adg_redirect)"
    # Làm sạch cấu hình dnsmasq trước
    sed -i '/no-resolv/d; /server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf

    if [ "$mode" = "1" ]; then
        # Mode 1: dnsmasq (53) -> AGH (5335)
        cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
        log "Mode 1: dnsmasq(53) forwarding to AGH(5335)"
    elif [ "$mode" = "2" ]; then
        # Mode 2: AGH (53) -> dnsmasq (5335)
        echo "port=5335" >> /etc/storage/dnsmasq/dnsmasq.conf
        log "Mode 2: AGH takes port 53, dnsmasq moved to 5335"
    fi
    /sbin/restart_dhcpd
}

del_dns() {
    sed -i '/no-resolv/d; /server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

# --- HÀM REDIRECT IPTABLES (Dành cho Mode 1) ---
set_iptable() {
    local mode="$(nvram get adg_redirect)"
    clear_iptable
    if [ "$mode" = "1" ]; then
        # Chỉ redirect khi AGH không chiếm cổng 53
        IPS="$(ifconfig br0 | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}')"
        for IP in $IPS; do
            iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335
            iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335
        done
        log "IPTables: Redirecting port 53 to 5335"
    fi
}

clear_iptable() {
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 5335 2>/dev/null
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5335 2>/dev/null
}

# --- TỐI ƯU CẤU HÌNH (Đẩy log sang RAM) ---
getconfig() {
    mkdir -p "$AGH_TMP"
    [ ! -f "$AGH_CFG" ] && return

    # Đồng bộ cổng DNS trong YAML cho khớp với Mode trên WebUI
    local mode="$(nvram get adg_redirect)"
    local target_p=5335
    [ "$mode" = "2" ] && target_p=53
    sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $target_p/" "$AGH_CFG"

    # Đẩy stats và querylog sang RAM (/tmp) để bảo vệ Flash
    mkdir -p /tmp/adguard-log
    if grep -q '^statistics:' "$AGH_CFG"; then
        sed -i '/^statistics:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
    fi
    if grep -q '^querylog:' "$AGH_CFG"; then
        sed -i '/^querylog:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
    fi
    sed -i 's/  file_enabled: true/  file_enabled: false/' "$AGH_CFG"
    log "Config patched: DNS Port=$target_p, Logs in RAM"
}

start_adg() {
    if pgrep AdGuardHome >/dev/null 2>&1; then return; fi

    getconfig
    export SSL_CERT_FILE=/etc_ro/ca-certificates.crt

    # Nếu Mode 2, phải giết dnsmasq trước để nhả cổng 53
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "2" ]; then
        killall dnsmasq 2>/dev/null
        sleep 1
    fi

    log "Starting AdGuardHome..."
    "$AGH_BIN_SRC" -c "$AGH_CFG" -w "$AGH_TMP" --no-check-update &

    # Chờ AGH bind cổng xong mới bật lại dnsmasq
    local retry=0
    local check_p=5335
    [ "$mode" = "2" ] && check_p=53
    
    while [ $retry -lt 10 ]; do
        if netstat -ulnp 2>/dev/null | grep -q ":$check_p "; then
            log "AGH bound port $check_p OK."
            break
        fi
        sleep 1
        retry=$((retry + 1))
    done

    change_dns
    set_iptable
}

stop_adg() {
    log "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
}

case $1 in
    start) start_adg ;;
    stop) stop_adg ;;
    restart) stop_adg; sleep 2; start_adg ;;
    status) pgrep AdGuardHome >/dev/null && echo "running" || echo "stopped" ;;
esac
