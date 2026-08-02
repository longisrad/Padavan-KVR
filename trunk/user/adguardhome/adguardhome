#!/bin/sh

AGH_BIN_SRC="/usr/bin/AdGuardHome"   # binary trong firmware, chạy thẳng
AGH_TMP="/etc/storage/AdGuardHome"   # work dir - persist qua reboot, đủ space
AGH_BIN="$AGH_BIN_SRC"               # chạy thẳng từ squashfs, không copy ra RAM
AGH_CFG="/etc/storage/AdGuardHome/AdGuardHome.yaml"  # config persist qua reboot

change_dns() {
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "1" ]; then
        # Mode 1: dnsmasq forward lên AGH port 5335
        sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
        sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
        cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
        /sbin/restart_dhcpd
        logger -t "AdGuardHome" "DNS: dnsmasq forwarding to AGH port 5335"
    elif [ "$mode" = "2" ]; then
        # Mode 2: tắt dnsmasq DNS listener, AGH listen port 53 trực tiếp
        sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
        echo "port=0" >> /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
        logger -t "AdGuardHome" "DNS: dnsmasq port disabled, AGH takes port 53"
    fi
}

del_dns() {
    sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=0/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

set_iptable() {
    local mode="$(nvram get adg_redirect)"
    # Mode 1: dnsmasq forward → AGH port 5335, cần redirect 53→5335 cho client ngoài
    # Mode 2: AGH giữ thẳng port 53 → KHÔNG redirect, redirect sẽ gây loop/fail
    if [ "$mode" = "1" ]; then
        IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
        for IP in $IPS; do
            iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
            iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        done
        IPS="$(ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}')"
        for IP in $IPS; do
            ip6tables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
            ip6tables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        done
        logger -t "AdGuardHome" "Mode 1: Redirecting port 53 to AGH port 5335"
    else
        logger -t "AdGuardHome" "Mode 2: AGH owns port 53 directly, no redirect needed"
    fi
}

clear_iptable() {
    IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
    for IP in $IPS; do
        iptables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        iptables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
    IPS="$(ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}')"
    for IP in $IPS; do
        ip6tables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        ip6tables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
}

load_binary() {
    if [ ! -f "$AGH_BIN_SRC" ]; then
        logger -t "AdGuardHome" "ERROR: Binary not found at $AGH_BIN_SRC"
        nvram set adg_enable=0
        exit 1
    fi
    mkdir -p "$AGH_TMP"
    logger -t "AdGuardHome" "Running binary directly from firmware (no RAM copy needed)"
}

getconfig() {
    mkdir -p /etc/storage/AdGuardHome

    if [ ! -f "$AGH_CFG" ] || [ ! -s "$AGH_CFG" ]; then
        logger -t "AdGuardHome" "No config found, AGH will auto-generate on first run"
        return
    fi

    # Tạo thư mục RAM cho stats
    mkdir -p /tmp/adguard-log

    # Chuyển statistics (stats.db) và querylog sang RAM - bảo vệ NAND
    # filters/ và sessions.db giữ trong NAND (cần persist qua reboot)
    if grep -q '^statistics:' "$AGH_CFG"; then
        sed -i '/^statistics:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
        logger -t "AdGuardHome" "Statistics dir set to RAM (/tmp/adguard-log)"
    fi
    if grep -q '^querylog:' "$AGH_CFG"; then
        sed -i '/^querylog:/,/^[a-z]/{s|  dir_path: ""|  dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
        logger -t "AdGuardHome" "Querylog dir set to RAM (/tmp/adguard-log)"
    fi

    # Xóa stats.db cũ trong NAND nếu còn tồn tại
    rm -f /etc/storage/AdGuardHome/data/stats.db

    # Tắt ghi file querylog (dùng memory buffer, vẫn xem được trong WebUI)
    sed -i 's/  file_enabled: true/  file_enabled: false/' "$AGH_CFG"

    logger -t "AdGuardHome" "Config patched: stats→RAM, querylog→memory"
}

start_adg() {
    if pgrep AdGuardHome >/dev/null 2>&1; then
        logger -t "AdGuardHome" "Already running, skipping start"
        return
    fi
    load_binary
    getconfig
    # Set CA certificates để AGH verify HTTPS khi download blocklists
    export SSL_CERT_FILE=/etc_ro/ca-certificates.crt

    logger -t "AdGuardHome" "Starting AdGuardHome..."
    if [ -f "$AGH_CFG" ] && [ -s "$AGH_CFG" ]; then
        "$AGH_BIN" -c "$AGH_CFG" -w "$AGH_TMP" --no-check-update &
        logger -t "AdGuardHome" "AdGuardHome started with config (PID: $!)"
    else
        "$AGH_BIN" -w "$AGH_TMP" --no-check-update &
        logger -t "AdGuardHome" "AdGuardHome started in setup mode port 3000 (PID: $!)"
    fi

    # Chờ AGH bind port 53 xong TRƯỚC khi đổi dnsmasq
    # Tránh race condition: khoảng trống DNS khi restart dnsmasq
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "2" ]; then
        logger -t "AdGuardHome" "Waiting for AGH to bind port 53..."
        local retry=0
        while [ $retry -lt 10 ]; do
            if netstat -tlnp 2>/dev/null | grep -q ":53 " && \
               netstat -ulnp 2>/dev/null | grep -q ":53 "; then
                logger -t "AdGuardHome" "AGH bound port 53 OK, now disabling dnsmasq DNS"
                change_dns
                break
            fi
            sleep 1
            retry=$((retry + 1))
        done
        if [ $retry -eq 10 ]; then
            logger -t "AdGuardHome" "WARNING: AGH did not bind port 53 after 10s"
            change_dns
        fi
    else
        change_dns
    fi
    set_iptable
}

stop_adg() {
    logger -t "AdGuardHome" "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
    # Không xóa AGH_TMP vì chứa config và data
    # Chỉ xóa lock/pid files nếu có
    rm -f "$AGH_TMP"/*.pid 2>/dev/null
    logger -t "AdGuardHome" "AdGuardHome stopped"
}

case $1 in
    start)
        start_adg
        ;;
    stop)
        stop_adg
        ;;
    restart)
        stop_adg
        sleep 1
        start_adg
        ;;
    status)
        if pgrep AdGuardHome >/dev/null 2>&1; then
            echo "AdGuardHome is running"
        else
            echo "AdGuardHome is stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        ;;
esac
