#!/bin/sh
TAG="CAKE_SQM"
IFB_IF="ifb0"

log() {
    logger -t "$TAG" "$1"
    echo "[$TAG] $1"
}

get_wan_ifname() {
    local iface=""
    if [ -d "/sys/class/net/ppp0" ]; then
        iface="ppp0"
    else
        iface=$(nvram get wan0_ifname)
        [ -z "$iface" ] && iface=$(nvram get wan_iface)
    fi
    [ -z "$iface" ] && iface="eth2.2"
    echo "$iface"
}

load_modules() {
    modprobe sch_cake 2>/dev/null
    modprobe ifb numifbs=1 2>/dev/null || modprobe ifb 2>/dev/null
    modprobe act_mirred 2>/dev/null
    modprobe cls_u32 2>/dev/null
    modprobe sch_ingress 2>/dev/null
}

stop_cake() {
    WAN_IF=$(get_wan_ifname)
    log "Dừng CAKE trên interface: $WAN_IF..."

    tc qdisc del dev "$WAN_IF" root 2>/dev/null
    tc qdisc del dev "$WAN_IF" ingress 2>/dev/null
    tc qdisc del dev "$IFB_IF" root 2>/dev/null
    ip link set dev "$IFB_IF" down 2>/dev/null

    # Khôi phục lại Hardware NAT nếu trước đó đã tắt tự động
    if [ "$(nvram get cake_drop_hwnat)" = "1" ] && [ "$(nvram get hw_nat_mode)" != "0" ]; then
        log "Khôi phục lại Hardware Acceleration (HW NAT)..."
        modprobe hw_nat 2>/dev/null
    fi

    log "Đã dừng CAKE thành công."
}

start_cake() {
    cake_enable=$(nvram get cake_enable)
    if [ "$cake_enable" != "1" ]; then
        stop_cake
        return 0
    fi

    # Tự động gỡ HW NAT nếu người dùng kích hoạt tùy chọn này
    if [ "$(nvram get cake_drop_hwnat)" = "1" ]; then
        log "Đang tắt tạm thời Hardware Acceleration để nhường quyền cho CAKE SQM..."
        rmmod hw_nat 2>/dev/null
    fi

    load_modules

    WAN_IF=$(get_wan_ifname)
    DOWN_BW=$(nvram get cake_down_bw)
    UP_BW=$(nvram get cake_up_bw)

    [ -z "$DOWN_BW" ] && DOWN_BW=0
    [ -z "$UP_BW" ] && UP_BW=0

    if [ "$UP_BW" -le 0 ]; then
        log "Lỗi: Tốc độ Upload phải lớn hơn 0!"
        return 1
    fi

    FLOW_MODE=$(nvram get cake_flow_mode)
    [ -z "$FLOW_MODE" ] && FLOW_MODE="triple-isolate"

    DIFFSERV=$(nvram get cake_diffserv)
    [ -z "$DIFFSERV" ] && DIFFSERV="diffserv4"

    case "$(nvram get cake_rtt)" in
        "metro")    RTT_PARAM="rtt 10ms" ;;
        "regional") RTT_PARAM="rtt 30ms" ;;
        "oceanic")  RTT_PARAM="rtt 300ms" ;;
        *)          RTT_PARAM="rtt 100ms" ;;
    esac

    case "$(nvram get cake_overhead)" in
        "ethernet") OVERHEAD_PARAM="ethernet overhead 14" ;;
        "atm")      OVERHEAD_PARAM="atm overhead 44" ;;
        "ptm")      OVERHEAD_PARAM="ptm overhead 8" ;;
        "docsis")   OVERHEAD_PARAM="docsis overhead 18" ;;
        *)          OVERHEAD_PARAM="overhead 0" ;;
    esac

    case "$(nvram get cake_ack_filter)" in
        "ack-filter")            ACK_PARAM="ack-filter" ;;
        "ack-filter-aggressive") ACK_PARAM="ack-filter-aggressive" ;;
        *)                       ACK_PARAM="" ;;
    esac

    [ "$(nvram get cake_nat)" = "1" ] && NAT_PARAM="nat" || NAT_PARAM=""
    [ "$(nvram get cake_wash)" = "1" ] && WASH_PARAM="wash" || WASH_PARAM=""
    CUSTOM_PARAM=$(nvram get cake_custom)

    stop_cake >/dev/null 2>&1

    log "Áp dụng CAKE Upload trên $WAN_IF (${UP_BW} Kbps)..."
    tc qdisc replace dev "$WAN_IF" root cake \
        bandwidth "${UP_BW}Kbit" \
        $FLOW_MODE \
        $DIFFSERV \
        $RTT_PARAM \
        $OVERHEAD_PARAM \
        $ACK_PARAM \
        $NAT_PARAM \
        $CUSTOM_PARAM

    # Nếu người dùng đặt Download > 0 thì mới kích hoạt IFB bóp Ingress
    if [ "$DOWN_BW" -gt 0 ]; then
        ip link set dev "$IFB_IF" up
        log "Áp dụng CAKE Download trên $IFB_IF (${DOWN_BW} Kbps)..."
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
    else
        log "Băng thông Download = 0 -> Thả nổi chiều tải xuống (chỉ quản lý Upload)."
    fi

    log "Khởi chạy CAKE SQM thành công!"
}

status_cake() {
    WAN_IF=$(get_wan_ifname)
    echo "==================== [UPLOAD QUEUE: $WAN_IF] ===================="
    tc -s qdisc show dev "$WAN_IF"
    echo ""
    echo "=================== [DOWNLOAD QUEUE: $IFB_IF] ==================="
    tc -s qdisc show dev "$IFB_IF" 2>/dev/null || echo "(Không kích hoạt IFB)"
}

case "$1" in
    start)   start_cake ;;
    stop)    stop_cake ;;
    restart) stop_cake; sleep 1; start_cake ;;
    status)  status_cake ;;
    *)       echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
exit 0
