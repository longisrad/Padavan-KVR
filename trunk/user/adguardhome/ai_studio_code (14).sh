#!/bin/sh
# AdGuardHome manager for Padavan - NEWIFI3 Build
# Logic: Stable logic (Wait for bind) + Auto Download + NAND Protection

AGH_BIN="/tmp/AdGuardHome/AdGuardHome"
AGH_TMP="/etc/storage/AdGuardHome"
AGH_CFG="/etc/storage/AdGuardHome/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"

# Link tải mipsle softfloat cho Newifi3
GH_DL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"

log() { logger -t "$LOG_TAG" "$1"; }

# --- 1. HÀM TẢI BINARY VỀ RAM ---
load_binary() {
    if [ -x "$AGH_BIN" ] && [ "$("$AGH_BIN" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    log "Binary not found in RAM. Downloading..."
    mkdir -p /tmp/AdGuardHome
    curl -Lksfo /tmp/AdGuardHome/agh.tar.gz "$GH_DL" || wget -q -O /tmp/AdGuardHome/agh.tar.gz "$GH_DL"
    
    tar -xzf /tmp/AdGuardHome/agh.tar.gz -C /tmp/AdGuardHome
    mv "$(find /tmp/AdGuardHome -type f -name AdGuardHome | head -n1)" "$AGH_BIN"
    chmod +x "$AGH_BIN"
    rm -rf /tmp/AdGuardHome/agh.tar.gz /tmp/AdGuardHome/AdGuardHome
    
    if [ ! -f "$AGH_BIN" ]; then
        log "ERROR: Failed to download binary"
        nvram set adg_enable=0
        exit 1
    fi
}

# --- 2. ĐỒNG BỘ DNS THEO MODE (Logic từ file ổn định) ---
change_dns() {
    local mode="$(nvram get adg_redirect)"
    # Dọn dẹp config cũ
    sed -i '/no-resolv/d; /server=127.0.0.1#5335/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf

    if [ "$mode" = "1" ]; then
        # Mode 1: dnsmasq forward lên AGH port 5335
        cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
        log "DNS: dnsmasq forwarding to AGH port 5335"
    elif [ "$mode" = "2" ]; then
        # Mode 2: tắt hoàn toàn DNS của dnsmasq, AGH port 53
        echo "port=0" >> /etc/storage/dnsmasq/dnsmasq.conf
        log "DNS: dnsmasq port disabled, AGH takes port 53"
    fi
    /sbin/restart_dhcpd
}

del_dns() {
    sed -i '/no-resolv/d; /server=127.0.0.1#5335/d; /^port=0/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

# --- 3. REDIRECT IPTABLES (Dành cho Mode 1) ---
set_iptable() {
    local mode="$(nvram get adg_redirect)"
    [ "$mode" != "1" ] && return
    
    IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
    for IP in $IPS; do
        iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
    log "Mode 1: Redirecting port 53 to 5335"
}

clear_iptable() {
    iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
}

# --- 4. TỐI ƯU CẤU HÌNH (Patch Port & RAM Log - Logic ổn định) ---
getconfig() {
    mkdir -p "$AGH_TMP"
    [ ! -f "$AGH_CFG" ] && return

    # Tự động sửa Port trong YAML cho khớp với Mode WebUI trước khi khởi chạy
    local mode="$(nvram get adg_redirect)"
    local target_p=5335
    [ "$mode" = "2" ] && target_p=53
    sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $target_p/" "$AGH_CFG"

    # Bảo vệ NAND: Đẩy Stats/QueryLog vào RAM
    mkdir -p /tmp/adguard-log
    if grep -q '^statistics:' "$AGH_CFG"; then
        sed -i '/^statistics:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
    fi
    if grep -q '^querylog:' "$AGH_CFG"; then
        sed -i '/^querylog:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
    fi
    # Tắt ghi file querylog (dùng memory buffer)
    sed -i 's/  file_enabled: true/  file_enabled: false/' "$AGH_CFG"
    log "Config patched: Port=$target_p, Logs pushed to RAM"
}

# --- 5. KHỞI CHẠY (Logic đợi Port bind thành công) ---
start_adg() {
    if [ "$(nvram get adg_enable)" != "1" ]; then stop_adg; return; fi
    if pgrep AdGuardHome >/dev/null 2>&1; then return; fi

    load_binary
    getconfig
    export SSL_CERT_FILE=/etc_ro/ca-certificates.crt

    log "Starting AdGuardHome..."
    if [ -f "$AGH_CFG" ] && [ -s "$AGH_CFG" ]; then
        "$AGH_BIN" -c "$AGH_CFG" -w "$AGH_TMP" --no-check-update &
    else
        log "Setup mode (Port 3000)..."
        "$AGH_BIN" -w "$AGH_TMP" --no-check-update &
    fi

    # Đợi AGH bind cổng xong mới cấu hình dnsmasq (Logic ổn định nhất)
    local mode="$(nvram get adg_redirect)"
    local check_p=5335
    [ "$mode" = "2" ] && check_p=53
    
    local retry=0
    while [ $retry -lt 15 ]; do
        if netstat -ulnp 2>/dev/null | grep -q ":$check_p "; then
            log "AGH bound port $check_p OK. Syncing DNS..."
            change_dns
            break
        fi
        sleep 1
        retry=$((retry + 1))
    done

    if [ $retry -eq 15 ]; then
        log "WARNING: AGH failed to bind port $check_p"
        change_dns
    fi
    set_iptable
}

stop_adg() {
    log "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
    rm -f "$AGH_TMP"/*.pid 2>/dev/null
}

case $1 in
    start) start_adg ;;
    stop) stop_adg ;;
    restart) stop_adg; sleep 2; start_adg ;;
    status) pgrep AdGuardHome >/dev/null && echo "running" || echo "stopped" ;;
esac