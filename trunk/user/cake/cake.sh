#!/bin/sh
# CAKE SQM cho Padavan - cấu hình đọc từ nvram (do trang Advanced_cake.asp ghi)
#   cake_enable      0|1
#   cake_down_bw     Kbit/s download (0 = không giới hạn chiều này)
#   cake_up_bw       Kbit/s upload   (0 = không giới hạn chiều này)
#   cake_flow_mode   auto|triple-isolate|flows|hosts|flowblind
#   cake_diffserv    besteffort|diffserv3|diffserv4|diffserv8
#   cake_rtt         internet|regional|metro|oceanic
#   cake_overhead    ethernet|pppoe|none|atm|ptm|docsis
#   cake_ack_filter  none|ack-filter|ack-filter-aggressive   (chỉ upload)
#   cake_nat         0|1
#   cake_wash        0|1                                     (chỉ download)
#   cake_custom      tham số bổ sung (chỉ chữ/số/khoảng trắng/. _ -)
#   cake_if          (tùy chọn) ép tên interface WAN; rỗng = tự dò (ppp0 nếu PPPoE, ngược lại wan_ifname)
# Dùng: cake.sh start|stop|restart|check|status [tên_interface_WAN]
# Tự cài: hook WAN-up vào /etc/storage/post_wan_script.sh (nếu file có) + cron kiểm tra mỗi 2 phút.

TAG="cake"
IFB="ifb0"
WAN_ARG="$2"
HOOKF="/etc/storage/post_wan_script.sh"
CRON_ID="cake_watch"
LOCK="/tmp/cake.lock"

log() { logger -t "$TAG" "$*"; echo "[$TAG] $*"; }
get() { v="$(nvram get "$1" 2>/dev/null)"; [ -n "$v" ] && echo "$v" || echo "$2"; }
isnum() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }

lock() {
  n=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    p="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
    n=$((n+1)); [ "$n" -ge 15 ] && { log "Đang có tiến trình CAKE khác chạy, bỏ qua"; return 1; }
    sleep 1
  done
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
  return 0
}

detect_wan() {
  W="$(get cake_if '')"
  [ -z "$W" ] && W="$WAN_ARG"
  if [ -z "$W" ]; then
    case "$(nvram get wan_proto 2>/dev/null)" in
      pppoe|pptp|l2tp) ip link show ppp0 >/dev/null 2>&1 && W="ppp0" ;;
    esac
  fi
  [ -z "$W" ] && W="$(nvram get wan_ifname 2>/dev/null)"
  case "$W" in *[!A-Za-z0-9._-]*) W="" ;; esac
  WAN="$W"
}

load_cfg() {
  ENABLE="$(get cake_enable 0)"
  detect_wan
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
    pppoe)    OVH_OPT="overhead 46 mpu 84" ;;   # PPPoE trên Ethernet/GPON, shaping trên ppp0
    none)     OVH_OPT="raw" ;;
    atm)      OVH_OPT="conservative" ;;
    ptm)      OVH_OPT="bridged-ptm" ;;
    docsis)   OVH_OPT="docsis" ;;
    *)        OVH_OPT="ethernet" ;;
  esac
  # chỉ giữ ký tự an toàn, tối đa 64 ký tự
  CUSTOM="$(echo "$CUSTOM" | tr -cd 'A-Za-z0-9 ._-' | cut -c1-64)"
}

install_autostart() {
  if [ -f "$HOOKF" ] && ! grep -q "CAKE_HOOK" "$HOOKF" 2>/dev/null; then
    printf '\n[ "$1" = "up" ] && /usr/bin/cake.sh restart "$2" >/dev/null 2>&1 &  # CAKE_HOOK\n' >> "$HOOKF"
    log "Đã cài hook WAN-up vào $HOOKF"
  fi
  command -v cru >/dev/null 2>&1 && cru a "$CRON_ID" "*/2 * * * * /usr/bin/cake.sh check" 2>/dev/null
}

remove_autostart() {
  [ -f "$HOOKF" ] && grep -q "CAKE_HOOK" "$HOOKF" 2>/dev/null && sed -i '/CAKE_HOOK/d' "$HOOKF"
  command -v cru >/dev/null 2>&1 && cru d "$CRON_ID" 2>/dev/null
}

# xóa qdisc trên mọi interface WAN có thể từng được áp (ppp0 hoặc wan_ifname...)
stop_cake() {
  for d in "$1" ppp0 "$(nvram get wan_ifname 2>/dev/null)"; do
    [ -n "$d" ] || continue
    ip link show "$d" >/dev/null 2>&1 || continue
    tc qdisc del dev "$d" root 2>/dev/null
    tc qdisc del dev "$d" ingress 2>/dev/null
  done
  tc qdisc del dev "$IFB" root 2>/dev/null
  ip link set "$IFB" down 2>/dev/null
}

offload_warn() {
  HW="$(nvram get hw_nat_mode 2>/dev/null)"
  SFE="$(nvram get sfe_enable 2>/dev/null)"
  if [ -n "$HW" ] && [ "$HW" != "2" ]; then
    log "CẢNH BÁO: Hardware NAT đang bật (hw_nat_mode=$HW), gói đi đường phần cứng sẽ bỏ qua CAKE"
  fi
  if [ -n "$SFE" ] && [ "$SFE" != "0" ]; then
    log "CẢNH BÁO: SFE đang bật (sfe_enable=$SFE), có thể làm CAKE không thấy hết lưu lượng"
  fi
}

is_applied() {
  [ "$UL" != 0 ] && { tc qdisc show dev "$WAN" 2>/dev/null | grep -q "qdisc cake" || return 1; }
  if [ "$DL" != 0 ]; then
    tc qdisc show dev "$IFB" 2>/dev/null | grep -q "qdisc cake" || return 1
    tc qdisc show dev "$WAN" 2>/dev/null | grep -q "ingress" || return 1
  fi
  return 0
}

start_cake() {
  load_cfg
  if [ "$ENABLE" != "1" ]; then remove_autostart; log "cake_enable=0, bỏ qua"; return 0; fi
  install_autostart
  if [ -z "$WAN" ] || ! ip link show "$WAN" >/dev/null 2>&1; then
    log "Chưa thấy WAN ($WAN), sẽ tự áp khi WAN lên"; return 1
  fi
  if [ "$DL" = 0 ] && [ "$UL" = 0 ]; then log "Cả hai tốc độ đều 0, không làm gì"; return 1; fi

  offload_warn
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
    if ! tc qdisc add dev "$WAN" handle ffff: ingress; then
      log "LỖI tạo ingress trên $WAN"; stop_cake "$WAN"; return 1
    fi
    if ! tc filter add dev "$WAN" parent ffff: protocol all prio 10 u32 match u32 0 0 \
         action mirred egress redirect dev "$IFB"; then
      log "LỖI chuyển hướng ingress sang $IFB (thiếu cls_u32/act_mirred?)"; stop_cake "$WAN"; return 1
    fi
    if tc qdisc add dev "$IFB" root cake bandwidth "${DL}kbit" $F $COMMON ingress $X $CUSTOM; then
      log "Download ${DL}Kbit/s qua $IFB"
    else
      log "LỖI đặt CAKE download trên $IFB"; stop_cake "$WAN"; return 1
    fi
  fi
  return 0
}

case "$1" in
  start)   lock || exit 1; start_cake ;;
  restart) lock || exit 1; load_cfg; [ "$ENABLE" = "1" ] || stop_cake "$WAN"; start_cake ;;
  stop)    load_cfg; remove_autostart; stop_cake "$WAN"; log "Đã tắt CAKE" ;;
  check)   lock || exit 0
           load_cfg
           [ "$ENABLE" = "1" ] || exit 0
           [ -n "$WAN" ] && ip link show "$WAN" >/dev/null 2>&1 || exit 0
           is_applied || { log "CAKE chưa/không còn áp dụng trên $WAN, áp lại"; start_cake; } ;;
  status)  load_cfg
           echo "enable=$ENABLE wan=$WAN down=${DL}Kbit up=${UL}Kbit flow=$FLOW diffserv=$DIFF rtt=$RTT overhead=$OVH nat=$NAT"
           echo "hw_nat_mode=$(nvram get hw_nat_mode 2>/dev/null) sfe_enable=$(nvram get sfe_enable 2>/dev/null) hook=$(grep -c CAKE_HOOK "$HOOKF" 2>/dev/null)"
           echo "--- $WAN ---"; tc -s qdisc show dev "$WAN" 2>&1
           echo "--- $IFB ---"; tc -s qdisc show dev "$IFB" 2>&1 ;;
  *) echo "Dùng: $0 start|stop|restart|check|status"; exit 1 ;;
esac
