#!/bin/sh
# CAKE SQM cho Padavan. Cấu hình đọc từ nvram (cake_*), do rc gọi: restart_cake.
# Dùng: cake.sh start|stop|restart|status|apply
PIDF=/var/run/cake.pid
IFB=ifb0

g()    { v=$(nvram get "$1" 2>/dev/null); if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi; }
log()  { logger -t cake "$*" 2>/dev/null; }
# tốc độ nhập theo Mbit (số nguyên/thập phân); 0 hoặc rỗng = không giới hạn
bw()   { case "$1" in ""|0|0.0) echo "";; *[!0-9.]*) echo "";; *) echo "bandwidth ${1}mbit";; esac; }

get_wan() {
  d=$(ip route 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  [ -n "$d" ] || d=$(nvram get wan_ifname 2>/dev/null)
  echo "$d"
}

clear_qdisc() {
  [ -n "$1" ] && { tc qdisc del dev "$1" root 2>/dev/null; tc qdisc del dev "$1" ingress 2>/dev/null; }
  tc qdisc del dev $IFB root 2>/dev/null
}

apply() {
  [ "$(g cake_enable 0)" = "1" ] || return 1

  DLBW=$(bw "$(g cake_down_bw 0)"); ULBW=$(bw "$(g cake_up_bw 0)")

  FM=$(g cake_flow_mode auto)
  case "$FM" in flowblind|srchost|dsthost|hosts|flows|dual-srchost|dual-dsthost|triple-isolate) ;; *) FM="" ;; esac
  DS=$(g cake_diffserv diffserv3)
  case "$DS" in besteffort|diffserv3|diffserv4|diffserv8) ;; *) DS=diffserv3 ;; esac
  RTT=$(g cake_rtt internet)
  case "$RTT" in datacentre|lan|metro|regional|internet|oceanic|satellite) ;; *) RTT=internet ;; esac
  OH=$(g cake_overhead ethernet)
  case "$OH" in raw|ethernet|ether-vlan|pppoe-ptm|bridged-ptm|docsis|conservative) ;; *) OH=ethernet ;; esac
  case "$(g cake_ack_filter none)" in ack-filter) AF="ack-filter" ;; ack-filter-aggressive) AF="ack-filter-aggressive" ;; *) AF="" ;; esac
  [ "$(g cake_nat 1)" = "1" ] && NAT=nat || NAT=nonat
  [ "$(g cake_wash 0)" = "1" ] && WASH=wash || WASH=""
  # tuỳ chọn thêm: chỉ cho ký tự an toàn
  CUSTOM=$(g cake_custom ""); echo "$CUSTOM" | grep -Eq '^[A-Za-z0-9 ._-]*$' || CUSTOM=""

  W=$(get_wan)
  [ -n "$W" ] && ip link show "$W" >/dev/null 2>&1 || return 2

  clear_qdisc "$W"
  ip link show $IFB >/dev/null 2>&1 || ip link add $IFB type ifb 2>/dev/null
  ip link set $IFB up
  tc qdisc add dev "$W" handle ffff: ingress &&
  tc filter add dev "$W" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $IFB &&
  tc qdisc replace dev $IFB root cake $DLBW $DS $FM $NAT $WASH ingress rtt $RTT $OH $CUSTOM &&
  tc qdisc replace dev "$W" root cake $ULBW $DS $FM $NAT $WASH rtt $RTT $OH $AF $CUSTOM || {
    log "loi ap dung tren $W"; return 3; }
  log "CAKE bat tren $W (down '${DLBW:-unlimited}', up '${ULBW:-unlimited}')"
  return 0
}

# vòng giám sát: áp dụng lại khi WAN kết nối lại (PPPoE/DHCP) làm mất qdisc
daemon() {
  while [ "$(g cake_enable 0)" = "1" ]; do
    W=$(get_wan)
    if [ -n "$W" ]; then
      { tc qdisc show dev "$W" 2>/dev/null | grep -q "qdisc cake" &&
        tc qdisc show dev $IFB 2>/dev/null | grep -q "qdisc cake"; } || apply
    fi
    sleep 15
  done
}

kill_daemon() { [ -f $PIDF ] && { kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; }; }

case "$1" in
  start)
    kill_daemon
    [ "$(g cake_enable 0)" = "1" ] || exit 0
    "$0" daemon >/dev/null 2>&1 &
    echo $! > $PIDF
    ;;
  daemon)  daemon ;;
  stop)    kill_daemon; clear_qdisc "$(get_wan)"; log "CAKE da tat" ;;
  restart) "$0" stop; "$0" start ;;
  apply)   apply ;;
  status)
    W=$(get_wan)
    echo "enable=$(g cake_enable 0)  wan=$W  daemon=$( [ -f $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null && echo chay || echo dung )"
    echo "--- $W (upload) ---";     tc -s qdisc show dev "$W" 2>&1 | head -14
    echo "--- $IFB (download) ---";  tc -s qdisc show dev $IFB 2>&1 | head -14
    ;;
  *) echo "Dung: $0 {start|stop|restart|status|apply}"; exit 1 ;;
esac
exit 0
