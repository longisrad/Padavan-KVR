#!/bin/sh
# ==============================================================================
# SCRIPT ĐỊNH TUYẾN HYBRID (TCP REDIRECT + UDP TPROXY + FAKEIP)
# Thiết bị: Newifi 3 D2 / Router Padavan / OpenWrt
# ==============================================================================

TCP_REDIR_PORT="7892"       # Inbound Redirect (TCP) trong sing-box
UDP_TPROXY_PORT="7893"      # Inbound TProxy (UDP) trong sing-box
DNS_PORT="5353"             # Inbound DNS trong sing-box
LAN_IFACE="br0"             # Cổng mạng LAN của Router

log() {
    logger -t "singbox-route" "$1"
    echo "[singbox-route] $1"
}

start_routing() {
    if [ -z "$(pidof sing-box)" ]; then
        log "CẢNH BÁO: Sing-box chưa chạy. Bỏ qua nạp định tuyến."
        return 1
    fi

    log "Đang áp dụng định tuyến HYBRID (TCP Redirect 7892 + UDP TProxy 7893)..."

    # 1. Nạp Module Kernel cần thiết
    for mod in nf_tproxy_core xt_TPROXY xt_socket xt_mark ip_set ip_set_hash_net xt_set; do
        modprobe $mod 2>/dev/null
    done

    # 2. Cấu hình Policy Routing Table 100 với ưu tiên cao nhất (pref 100) cho UDP TProxy
    while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
    while ip rule del pref 100 2>/dev/null; do :; done
    ip route flush table 100 2>/dev/null
    ip rule add fwmark 1 table 100 pref 100 2>/dev/null
    ip route add local default dev lo table 100 2>/dev/null

    # 3. Tạo IPSet bỏ qua IP nội bộ (LAN Bypass)
    ipset create singbox_bypass hash:net 2>/dev/null
    ipset flush singbox_bypass 2>/dev/null
    for cidr in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
        ipset add singbox_bypass $cidr 2>/dev/null
    done

    # 4. BẺ LÁI TCP SANG NAT REDIRECT (CỔNG 7892) - Ổn định tuyệt đối trên Padavan
    iptables -t nat -N SINGBOX_TCP 2>/dev/null
    iptables -t nat -F SINGBOX_TCP 2>/dev/null
    iptables -t nat -A SINGBOX_TCP -m set --match-set singbox_bypass dst -j RETURN
    iptables -t nat -A SINGBOX_TCP -p tcp -j REDIRECT --to-ports $TCP_REDIR_PORT

    while iptables -t nat -D PREROUTING -i $LAN_IFACE -p tcp -j SINGBOX_TCP 2>/dev/null; do :; done
    iptables -t nat -I PREROUTING -i $LAN_IFACE -p tcp -j SINGBOX_TCP 2>/dev/null

    # 5. BẺ LÁI UDP SANG MANGLE TPROXY (CỔNG 7893) - Dành cho Game/QUIC
    iptables -t mangle -N SINGBOX_UDP 2>/dev/null
    iptables -t mangle -F SINGBOX_UDP 2>/dev/null
    iptables -t mangle -A SINGBOX_UDP -m set --match-set singbox_bypass dst -j RETURN
    iptables -t mangle -A SINGBOX_UDP -p udp -j TPROXY --on-port $UDP_TPROXY_PORT --tproxy-mark 1

    while iptables -t mangle -D PREROUTING -i $LAN_IFACE -p udp -j SINGBOX_UDP 2>/dev/null; do :; done
    iptables -t mangle -I PREROUTING -i $LAN_IFACE -p udp -j SINGBOX_UDP 2>/dev/null

    # 6. Mở khóa Kernel cho TProxy (ip_nonlocal_bind & rp_filter)
    echo 1 > /proc/sys/net/ipv4/ip_nonlocal_bind 2>/dev/null
    for f in /proc/sys/net/ipv4/conf/*/rp_filter; do
        echo 0 > "$f" 2>/dev/null
    done

    # 7. Chuyển hướng DNS mạng LAN (Port 53 -> Port 5353) nếu bật tuỳ chọn
    if [ "$(nvram get singbox_dns_redirect 2>/dev/null)" = "1" ]; then
        iptables -t nat -N SINGBOX_DNS 2>/dev/null
        iptables -t nat -F SINGBOX_DNS 2>/dev/null
        iptables -t nat -A SINGBOX_DNS -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT
        iptables -t nat -A SINGBOX_DNS -p tcp --dport 53 -j REDIRECT --to-ports $DNS_PORT

        while iptables -t nat -D PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null; do :; done
        iptables -t nat -I PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null
    else
        while iptables -t nat -D PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null; do :; done
        iptables -t nat -F SINGBOX_DNS 2>/dev/null
        iptables -t nat -X SINGBOX_DNS 2>/dev/null
    fi

    # 8. Xoá 127.0.0.1 và tự bù DNS dự phòng nếu file rỗng
    if [ -f /etc/resolv.conf ]; then
        sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.conf
        if ! grep -q "^nameserver" /etc/resolv.conf; then
            echo "nameserver 1.1.1.1" > /etc/resolv.conf
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        fi
    fi

    log "Đã kích hoạt định tuyến HYBRID thành công!"
    return 0
}

stop_routing() {
    log "Đang gỡ bỏ cấu hình định tuyến..."

    # Gỡ chuỗi TCP Redirect (NAT)
    while iptables -t nat -D PREROUTING -i $LAN_IFACE -p tcp -j SINGBOX_TCP 2>/dev/null; do :; done
    ipt
