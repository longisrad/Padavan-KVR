#!/bin/sh
# ==============================================================================
# SCRIPT ĐỊNH TUYẾN TPROXY & FAKEIP DÀNH CHO SING-BOX & ADGUARD HOME
# Thiết bị: Newifi 3 D2 / Router Padavan / OpenWrt
# Đường dẫn lưu trữ: /etc/storage/singbox_route.sh
# ==============================================================================

TPROXY_PORT="7893"          # Cổng Inbound TProxy trong config Sing-box
DNS_PORT="5353"             # Cổng Inbound DNS trong config Sing-box
FAKEIP_RANGE="198.18.0.0/15" # Dải FakeIP của Sing-box
LAN_IFACE="br0"             # Cổng mạng LAN của Router Padavan

log() {
    logger -t "singbox-route" "$1"
    echo "[singbox-route] $1"
}

start_routing() {
    # 1. Kiểm tra nếu Sing-box chưa chạy thì không nạp quy tắc
    if [ -z "$(pidof sing-box)" ]; then
        log "CẢNH BÁO: Sing-box hiện chưa chạy. Bỏ qua nạp định tuyến."
        return 1
    fi

    log "Đang áp dụng cấu hình định tuyến TProxy & FakeIP..."

    # 2. Nạp các Module Kernel TProxy cần thiết
    # ip_set/ip_set_hash_net/xt_set: BAT BUOC de "-m set --match-set" (dong
    # duoi) hoat dong. Neu thieu, lenh iptables -A voi -m set co the fail
    # am tham tuy kernel build (mot so build co san san, mot so khong).
    for mod in nf_tproxy_core xt_TPROXY xt_socket xt_mark ip_set ip_set_hash_net xt_set; do
        modprobe $mod 2>/dev/null
    done

    # 3. Tạo Bảng định tuyến Policy Routing (Table 100)
    while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
    ip rule add fwmark 1 table 100 2>/dev/null
    ip route add local default dev lo table 100 2>/dev/null

    # 4. Tạo IPSet chứa danh sách các IP nội bộ cần bỏ qua (Bypass LAN)
    ipset create singbox_bypass hash:net 2>/dev/null
    ipset flush singbox_bypass 2>/dev/null
    for cidr in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
        ipset add singbox_bypass $cidr 2>/dev/null
    done

    # 5. Bẻ lái Traffic từ thiết bị LAN đi qua TProxy (Mangle Table)
    iptables -t mangle -N SINGBOX 2>/dev/null
    iptables -t mangle -F SINGBOX 2>/dev/null
    
    # Bỏ qua truy cập IP nội bộ
    iptables -t mangle -A SINGBOX -m set --match-set singbox_bypass dst -j RETURN
    
    # Đánh dấu fwmark 1 và đẩy vào cổng TProxy 7893
    iptables -t mangle -A SINGBOX -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
    iptables -t mangle -A SINGBOX -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark 1
    
    # Nhúng quy tắc vào cổng LAN br0
    while iptables -t mangle -D PREROUTING -i $LAN_IFACE -j SINGBOX 2>/dev/null; do :; done
    iptables -t mangle -I PREROUTING -i $LAN_IFACE -j SINGBOX 2>/dev/null

    # 6. FIX LỖI FAKEIP CHO ADGUARD HOME / ROUTER (OUTPUT Chain)
    # Bẻ lái gói tin FakeIP xuất phát từ chính Router về Sing-box
    iptables -t nat -C OUTPUT -d $FAKEIP_RANGE -p tcp -j REDIRECT --to-ports $TPROXY_PORT 2>/dev/null || \
    iptables -t nat -A OUTPUT -d $FAKEIP_RANGE -p tcp -j REDIRECT --to-ports $TPROXY_PORT

    iptables -t nat -C OUTPUT -d $FAKEIP_RANGE -p udp -j REDIRECT --to-ports $TPROXY_PORT 2>/dev/null || \
    iptables -t nat -A OUTPUT -d $FAKEIP_RANGE -p udp -j REDIRECT --to-ports $TPROXY_PORT

    # 7. Chuyển hướng DNS toàn mạng LAN (Port 53 -> Port 5353)
    # CHI ap dung khi nvram singbox_dns_redirect=1. Neu tat (=0), nghia la
    # AGH dang tu bind thang port 53 (mode 2) - KHONG duoc redirect de tranh
    # tao vong lap redirect (bug da tung gap va fix truoc day: AGH nhan tren
    # 53, bi redirect nguoc lai chinh no qua 5353 -> loop/timeout).
    if [ "$(nvram get singbox_dns_redirect 2>/dev/null)" = "1" ]; then
        iptables -t nat -N SINGBOX_DNS 2>/dev/null
        iptables -t nat -F SINGBOX_DNS 2>/dev/null
        iptables -t nat -A SINGBOX_DNS -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT
        iptables -t nat -A SINGBOX_DNS -p tcp --dport 53 -j REDIRECT --to-ports $DNS_PORT

        while iptables -t nat -D PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null; do :; done
        iptables -t nat -I PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null
    else
        # Dam bao don sach chain nay neu truoc day da bat roi tat lai -
        # tranh sot rule redirect cu tu lan start truoc.
        while iptables -t nat -D PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null; do :; done
        iptables -t nat -F SINGBOX_DNS 2>/dev/null
        iptables -t nat -X SINGBOX_DNS 2>/dev/null
    fi

    # 8. Gỡ 127.0.0.1 khỏi resolv.conf của Router để tránh lặp DNS
    if [ -f /etc/resolv.conf ] && grep -q "^nameserver 127.0.0.1$" /etc/resolv.conf; then
        sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.conf
    fi

    log "Đã kích hoạt toàn bộ quy tắc định tuyến TProxy & FakeIP thành công!"
}

stop_routing() {
    log "Đang gỡ bỏ cấu hình định tuyến..."

    # Gỡ chuỗi TProxy khỏi Mangle PREROUTING
    while iptables -t mangle -D PREROUTING -i $LAN_IFACE -j SINGBOX 2>/dev/null; do :; done
    iptables -t mangle -F SINGBOX 2>/dev/null
    iptables -t mangle -X SINGBOX 2>/dev/null

    # Gỡ chuỗi DNS khỏi NAT PREROUTING
    while iptables -t nat -D PREROUTING -i $LAN_IFACE -j SINGBOX_DNS 2>/dev/null; do :; done
    iptables -t nat -F SINGBOX_DNS 2>/dev/null
    iptables -t nat -X SINGBOX_DNS 2>/dev/null

    # Gỡ bẻ lái FakeIP Output
    while iptables -t nat -D OUTPUT -d $FAKEIP_RANGE -p tcp -j REDIRECT --to-ports $TPROXY_PORT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -d $FAKEIP_RANGE -p udp -j REDIRECT --to-ports $TPROXY_PORT 2>/dev/null; do :; done

    # Xóa Bảng định tuyến Table 100 & IPSet
    while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
    ip route del local default dev lo table 100 2>/dev/null
    ipset destroy singbox_bypass 2>/dev/null

    log "Đã gỡ bỏ sạch sẽ các quy tắc định tuyến."
}

case "$1" in
    start|apply)
        start_routing
        ;;
    stop|clean)
        stop_routing
        ;;
        
    restart)
        stop_routing
        sleep 1
        start_routing
        ;;
    status)
        if iptables -t mangle -L PREROUTING -n -v | grep -q SINGBOX; then
            echo "Trạng thái định tuyến: ĐANG BẬT (ACTIVE)"
        else
            echo "Trạng thái định tuyến: ĐÃ TẮT (INACTIVE)"
        fi
        ;;
    *)
        echo "Cú pháp sử dụng: $0 {start|stop|restart|status}"
        ;;
esac