#!/bin/sh
# CAKE SQM cho Padavan - cấu hình đọc từ nvram (do trang Advanced_cake.asp ghi)
#   cake_enable      0|1
#   cake_down_bw     Kbit/s download (0 = không giới hạn chiều này)
#   cake_up_bw       Kbit/s upload   (0 = không giới hạn chiều này)
#   cake_flow_mode   auto|triple-isolate|flows|hosts|flowblind
#   cake_diffserv    besteffort|diffserv3|diffserv4|diffserv8
#   cake_rtt         internet|regional|metro|oceanic
#   cake_overhead    ethernet|none|atm|ptm|docsis
#   cake_ack_filter  none|ack-filter|ack-filter-aggressive   (chỉ upload)
#   cake_nat         0|1
#   cake_wash        0|1                                     (chỉ download)
#   cake_custom      tham số bổ sung (chỉ chữ/số/khoảng trắng/. _ -)
#   cake_if          (tùy chọn) ép tên interface WAN; rỗng = wan_ifname
# Dùng: cake.sh start|stop|restart|status [tên_interface_WAN]
#   Gọi từ "Run After WAN Up/Down": [ "$1" = "up" ] && /usr/bin/cake.sh restart "$2" &

TAG="cake"
IFB="ifb0"
WAN_ARG="$2"

log() { logger -t "$TAG" "$*"; echo "[$TAG] $*"; }
get() { v="$(nvram get "$1" 2>/dev/null)"; [ -n "$v" ] && echo "$v" || echo "$2"; }
isnum() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

load_cfg() {
  ENABLE="$(get cake_enable 0)"
  WAN="$(get cake_if '')"
  [ -z "$WAN" ] && WAN="$WAN_ARG"
  [ -z "$WAN" ] && WAN="$(nvram get wan_ifname 2>/dev/null)"
  case "$WAN" in *[!A-Za-z0-9._-]*) WAN="" ;; esac
  DL="$(get cake_down_bw 0)"
  UL="$(get cake_up_bw 0)"
  FLOW="$(get cake_flow_mode auto)"
  DIFF="$(get cake_diffserv diffserv3)"
  RTT="$(get cake_rtt internet)"
  OVH="$(get cake_overhead ethernet)"
  ACK="$(get cake_ack_filter none)"
  NAT="$(get cake_nat 1)"
  WASH="$(get cake_wash 0)"
  CUSTOM="$(get cake_custom '')"

  isnum "$DL" || DL=0
  isnum "$UL" || UL=0
  case "$FLOW" in auto|triple-isolate|flows|hosts|flowblind) ;; *) FLOW=auto;; esac
  case "$DIFF" in besteffort|diffserv3|diffserv4|diffserv8) ;; *) DIFF=diffserv3;; esac
  case "$RTT" in internet|regional|metro|oceanic) ;; *) RTT=internet;; esac
  case "$ACK" in none|ack-filter|ack-filter-aggressive) ;; *) ACK=none;; esac
  case "$OVH" in
    ethernet) OVH_OPT="ethernet" ;;
    none)     OVH_OPT="raw" ;;
    atm)      OVH_OPT="conservative" ;;
    ptm)      OVH_OPT="bridged-ptm" ;;
    docsis)   OVH_OPT="docsis" ;;
    *)        OVH_OPT="ethernet" ;;
  esac
  # chỉ giữ ký tự an toàn, tối đa 64 ký tự
  CUSTOM="$(echo "$CUSTOM" | tr -cd 'A-Za-z0-9 ._-' | cut -c1-64)"
}

stop_cake() {
  W="$1"
  if [ -n "$W" ]; then
    tc qdisc del dev "$W" root 2>/dev/null
    tc qdisc del dev "$W" ingress 2>/dev/null
  fi
  tc qdisc del dev "$IFB" root 2>/dev/null
  ip link set "$IFB" down 2>/dev/null
}

start_cake() {
  load_cfg
  if [ "$ENABLE" != "1" ]; then log "cake_enable=0, bỏ qua"; return 0; fi
  if [ -z "$WAN" ] || ! ip link show "$WAN" >/dev/null 2>&1; then log "Không tìm thấy WAN ($WAN)"; return 1; fi
  if [ "$DL" = 0 ] && [ "$UL" = 0 ]; then log "Cả hai tốc độ đều 0, không làm gì"; return 1; fi

  if lsmod 2>/dev/null | grep -q '^hw_nat'; then
    log "CẢNH BÁO: hw_nat đang nạp, gói đi đường phần cứng sẽ bỏ qua CAKE"
  fi

  stop_cake "$WAN"
  set -f   # tắt globbing khi mở rộng biến không đặt trong nháy

  COMMON="$DIFF $OVH_OPT $RTT"
  [ "$NAT" = 1 ] && COMMON="$COMMON nat" || COMMON="$COMMON nonat"

  # Upload (egress trên WAN)
  if [ "$UL" != 0 ]; then
    F="$FLOW"; [ "$F" = auto ] && F="dual-srchost"
    X=""; [ "$ACK" != none ] && X="$ACK"
    if tc qdisc add dev "$WAN" root cake bandwidth "${UL}kbit" $F $COMMON $X $CUSTOM; then
      log "Upload ${UL}Kbit/s trên $WAN"
    else
      log "LỖI đặt CAKE upload trên $WAN"; stop_cake "$WAN"; return 1
    fi
  fi

  # Download (ingress -> IFB)
  if [ "$DL" != 0 ]; then
    ip link show "$IFB" >/dev/null 2>&1 || ip link add "$IFB" type ifb 2>/dev/null
    if ! ip link set "$IFB" up 2>/dev/null; then log "Không bật được $IFB"; stop_cake "$WAN"; return 1; fi
    F="$FLOW"; [ "$F" = auto ] && F="dual-dsthost"
    X=""; [ "$WASH" = 1 ] && X="wash"
    tc qdisc add dev "$WAN" handle ffff: ingress 2>/dev/null
    tc filter add dev "$WAN" parent ffff: protocol all prio 10 u32 match u32 0 0 \
       action mirred egress redirect dev "$IFB" 2>/dev/null
    if tc qdisc add dev "$IFB" root cake bandwidth "${DL}kbit" $F $COMMON ingress $X $CUSTOM; then
      log "Download ${DL}Kbit/s qua $IFB"
    else
      log "LỖI đặt CAKE download trên $IFB"; stop_cake "$WAN"; return 1
    fi
  fi
  return 0
}

case "$1" in
  start)   start_cake ;;
  stop)    load_cfg; stop_cake "$WAN"; log "Đã tắt CAKE" ;;
  restart) load_cfg; stop_cake "$WAN"; start_cake ;;
  status)  load_cfg
           echo "enable=$ENABLE wan=$WAN down=${DL}Kbit up=${UL}Kbit flow=$FLOW diffserv=$DIFF rtt=$RTT overhead=$OVH nat=$NAT"
           echo "--- $WAN ---"; tc -s qdisc show dev "$WAN" 2>&1
           echo "--- $IFB ---"; tc -s qdisc show dev "$IFB" 2>&1 ;;
  *) echo "Dùng: $0 start|stop|restart|status"; exit 1 ;;
esac
