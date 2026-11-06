#!/bin/sh
#################################################################
# Script điều khiển CAKE SQM cho Padavan Firmware
# Tương thích với trang cấu hình Advanced_cake.asp
#################################################################

TAG="CAKE_SQM"
IFB_IF="ifb0"

log() {
    logger -t "$TAG" "$1"
    echo "[$TAG] $1"
}

# Lấy interface WAN thực tế đang kết nối (hỗ trợ DHCP, Static IP, PPPoE)
get_wan_ifname() {
    local iface=""
    # Kiểm tra nếu PPPoE đang chạy
    if [ -d "/sys/class/net/ppp0" ]; then
        iface="ppp0"
    else
        iface=$(nvram get wan0_ifname)
        [ -z "$iface" ] && iface=$(nvram get wan_iface)
    fi
    [ -z "$iface" ] && iface="eth2.2"
    echo "$iface"
}

# Nạp các Kernel Modules cần thiết cho CAKE và IFB
load_modules() {
    modprobe sch_cake 2>/dev/null
    modprobe ifb numifbs=1 2>/dev/null || modprobe ifb 2>/dev/null
    modprobe act_mirred 2>/dev/null
    modprobe cls_u32 2>/dev/null
    modprobe sch_ingress 2>/dev/null
}

# Dọn dẹp hàng đợi cũ
stop_cake() {
    WAN_IF=$(get_wan_ifname)
    log "Đang dừng CAKE trên interface: WAN=$WAN_IF, IFB=$IFB_IF..."

    # Xóa qdisc trên interface WAN
    tc qdisc del dev "$WAN_IF" root 2>/dev/null
    tc qdisc del dev "$WAN_IF" ingress 2>/dev/null

    # Xóa qdisc trên interface ảo IFB
    tc qdisc del dev "$IFB_IF" root 2>/dev/null
    ip link set dev "$IFB_IF" down 2>/dev/null

    log "Đã dừng CAKE thành công."
}

# Khởi chạy và thiết lập CAKE
start_cake() {
    cake_enable=$(nvram get cake_enable)
    if [ "$cake_enable" != "1" ]; then
        log "Tính năng CAKE chưa được bật trong NVRAM."
        stop_cake
        return 0
    fi

    load_modules

    WAN_IF=$(get_wan_ifname)
    DOWN_BW=$(nvram get cake_down_bw)
    UP_BW=$(nvram get cake_up_bw)

    if [ -z "$DOWN_BW" ] || [ -z "$UP_BW" ] || [ "$DOWN_BW" -le 0 ] || [ "$UP_BW" -le 0 ]; then
        log "Lỗi: Tốc độ Download hoặc Upload không hợp lệ!"
        return 1
    fi

    # Lấy các tùy chọn từ NVRAM (ASP Form)
    FLOW_MODE=$(nvram get cake_flow_mode)
    [ -z "$FLOW_MODE" ] && FLOW_MODE="triple-isolate"

    DIFFSERV=$(nvram get cake_diffserv)
    [ -z "$DIFFSERV" ] && DIFFSERV="diffserv4"

    # Xử lý RTT
    CAKE_RTT_OPT=$(nvram get cake_rtt)
    case "$CAKE_RTT_OPT" in
        "metro")    RTT_PARAM="rtt 10ms" ;;
        "regional") RTT_PARAM="rtt 30ms" ;;
        "oceanic")  RTT_PARAM="rtt 300ms" ;;
        *)          RTT_PARAM="rtt 100ms" ;;
    esac

    # Xử lý Framing / Overhead
    OVERHEAD_OPT=$(nvram get cake_overhead)
    case "$OVERHEAD_OPT" in
        "ethernet") OVERHEAD_PARAM="ethernet overhead 14" ;;
        "atm")      OVERHEAD_PARAM="atm overhead 44" ;;
        "ptm")      OVERHEAD_PARAM="ptm overhead 8" ;;
        "docsis")   OVERHEAD_PARAM="docsis overhead 18" ;;
        *)          OVERHEAD_PARAM="overhead 0" ;;
    esac

    # Lọc ACK (chỉ áp dụng cho Upload)
    ACK_FILTER_OPT=$(nvram get cake_ack_filter)
    case "$ACK_FILTER_OPT" in
        "ack-filter")            ACK_PARAM="ack-filter" ;;
        "ack-filter-aggressive") ACK_PARAM="ack-filter-aggressive" ;;
        *)                       ACK_PARAM="" ;;
    esac

    # Cờ NAT
    [ "$(nvram get cake_nat)" = "1" ] && NAT_PARAM="nat" || NAT_PARAM=""

    # Cờ Wash (thường áp dụng cho Download)
    [ "$(nvram get cake_wash)" = "1" ] && WASH_PARAM="wash" || WASH_PARAM=""

    # Tùy biến mở rộng
    CUSTOM_PARAM=$(nvram get cake_custom)

    # 1. Dọn dẹp trước khi thiết lập
    stop_cake >/dev/null 2>&1

    # Bật interface IFB
    ip link set dev "$IFB_IF" up
    if [ $? -ne 0 ]; then
        log "Lỗi: Không thể khởi động thiết bị $IFB_IF!"
        return 1
    fi

    log "Đang áp dụng CAKE trên $WAN_IF (DL: ${DOWN_BW} Kbps, UL: ${UP_BW} Kbps)..."

    # 2. Cấu hình UPLOAD (Egress trên WAN interface)
    tc qdisc replace dev "$WAN_IF" root cake \
        bandwidth "${UP_BW}Kbit" \
        $FLOW_MODE \
        $DIFFSERV \
        $RTT_PARAM \
        $OVERHEAD_PARAM \
        $ACK_PARAM \
        $NAT_PARAM \
        $CUSTOM_PARAM

    # 3. Cấu hình DOWNLOAD (Ingress redirect sang IFB interface)
    tc qdisc add dev "$WAN_IF" handle ffff: ingress
    tc filter add dev "$WAN_IF" parent ffff: protocol all prio 1 u32 \
        match u32 0 0 \
        action mirred egress redirect dev "$IFB_IF"

    tc qdisc replace dev "$IFB_IF" root cake \
        bandwidth "${DOWN_BW}Kbit" \
        $FLOW_MODE \
        $DIFFSERV \
        $RTT_PARAM \
        $OVERHEAD_PARAM \
        $WASH_PARAM \
        $NAT_PARAM \
        $CUSTOM_PARAM

    log "Khởi chạy CAKE SQM thành công!"
}

# Xem thống kê chi tiết luồng, độ trễ và drops của CAKE
status_cake() {
    WAN_IF=$(get_wan_ifname)
    echo "==================== [UPLOAD STATUS: $WAN_IF] ===================="
    tc -s qdisc show dev "$WAN_IF"
    echo ""
    echo "=================== [DOWNLOAD STATUS: $IFB_IF] ==================="
    tc -s qdisc show dev "$IFB_IF"
}

case "$1" in
    start)
        start_cake
        ;;
    stop)
        stop_cake
        ;;
    restart)
        stop_cake
        sleep 1
        start_cake
        ;;
    status)
        status_cake
        ;;
    *)
        echo "Cách sử dụng: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
