#!/bin/sh
# CAKE SQM cho Padavan (MT7621). Cau hinh doc tu nvram (cake_*), do rc goi: restart_cake.
# Dung: cake.sh start|stop|restart|status|apply|check
PIDF=/var/run/cake.pid
WANF=/var/run/cake.wan
IFB=ifb0

g()   { v=$(nvram get "$1" 2>/dev/null); if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi; }
log() { logger -t cake "$*" 2>/dev/null; }
# toc do nhap theo Mbit (so nguyen/thap phan); 0 / rong / sai dinh dang = khong gioi han
bw()  {
  echo "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || { echo ""; return; }
  if awk -v x="$1" 'BEGIN{exit !(x+0>0)}'; then echo "bandwidth ${1}mbit"; else echo ""; fi
}

# WAN = dev cua default route, bo qua tun/tailscale/wireguard/ifb (sing-box TUN co the chiem default route)
get_wan() {
  d=$(ip route 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev" && $(i+1) !~ /^(tun|tap|tailscale|ts[0-9]|wg|ifb|singbox|utun)/){print $(i+1); exit}}')
  [ -n "$d" ] || d=$(nvram get wan_ifname 2>/dev/null)
  echo "$d"
}

clear_qdisc() {
  for d in "$@"; do
    [ -n "$d" ] || continue
    tc qdisc del dev "$d" root 2>/dev/null
    tc qdisc del dev "$d" ingress 2>/dev/null
  done
  tc qdisc del dev $IFB root 2>/dev/null
}

# CAKE (va hook ingress neu co gioi han download) con hieu luc tren WAN $1 khong
is_active() {
  tc qdisc show dev "$1" 2>/dev/null | grep -q "qdisc cake" || return 1
  if [ -n "$(bw "$(g cake_down_bw 0)")" ]; then
    tc qdisc show dev $IFB 2>/dev/null | grep -q "qdisc cake" || return 1
    tc filter show dev "$1" parent ffff: 2>/dev/null | grep -q "$IFB" || return 1
  fi
  return 0
}

apply() {
  [ "$(g cake_enable 0)" = "1" ] || return 1

  DLBW=$(bw "$(g cake_down_bw 0)"); ULBW=$(bw "$(g cake_up_bw 0)")

  [ "$(g cake_nat 1)" = "1" ] && NAT=nat || NAT=nonat
  FM=$(g cake_flow_mode auto)
  # chia luong: per-host dung chieu (upload = src host, download = dst host)
  case "$FM" in
    auto)
      if [ "$NAT" = nat ]; then FMU=dual-srchost; FMD=dual-dsthost; else FMU=triple-isolate; FMD=triple-isolate; fi ;;
    dual-srchost|dual-dsthost) FMU=dual-srchost; FMD=dual-dsthost ;;
    srchost|dsthost)           FMU=srchost;      FMD=dsthost ;;
    flowblind|hosts|flows|triple-isolate) FMU=$FM; FMD=$FM ;;
    *) FMU=triple-isolate; FMD=triple-isolate ;;
  esac
  DS=$(g cake_diffserv diffserv3)
  case "$DS" in besteffort|diffserv3|diffserv4|diffserv8) ;; *) DS=diffserv3 ;; esac
  RTT=$(g cake_rtt internet)
  case "$RTT" in datacentre|lan|metro|regional|internet|oceanic|satellite) ;; *) RTT=internet ;; esac
  OH=$(g cake_overhead ethernet)
  case "$OH" in raw|ethernet|ether-vlan|pppoe-ptm|bridged-ptm|docsis|conservative) ;; *) OH=ethernet ;; esac
  case "$(g cake_ack_filter none)" in ack-filter) AF="ack-filter" ;; ack-filter-aggressive) AF="ack-filter-aggressive" ;; *) AF="" ;; esac
  # wash chi ap dung cho download (ingress); upload luon giu DSCP
  [ "$(g cake_wash 0)" = "1" ] && WASH=wash || WASH=""
  # tuy chon them: chi cho ky tu an toan
  CUSTOM=$(g cake_custom ""); echo "$CUSTOM" | grep -Eq '^[A-Za-z0-9 ._-]*$' || CUSTOM=""

  W=$(get_wan)
  [ -n "$W" ] && ip link show "$W" >/dev/null 2>&1 || return 2

  # WAN doi (vd eth3 -> ppp0 luc PPPoE len): go CAKE khoi dev cu, tranh shape 2 lan
  OLD=$(cat $WANF 2>/dev/null)
  [ -n "$OLD" ] && [ "$OLD" != "$W" ] && clear_qdisc "$OLD"
  clear_qdisc "$W"
  echo "$W" > $WANF

  [ -z "$DLBW" ] && [ -z "$ULBW" ] && log "chua dat toc do up/down: CAKE chi chia luong, khong giam bufferbloat"

  # upload (egress tren WAN)
  tc qdisc replace dev "$W" root cake $ULBW $DS $FMU $NAT nowash rtt $RTT $OH $AF $CUSTOM || {
    log "loi ap dung egress tren $W"; clear_qdisc "$W"; return 3; }

  # download (ingress -> ifb0): chi dung khi co dat gioi han download, tiet kiem CPU
  if [ -n "$DLBW" ]; then
    ip link show $IFB >/dev/null 2>&1 || ip link add $IFB type ifb 2>/dev/null
    ip link set $IFB up
    tc qdisc add dev "$W" handle ffff: ingress &&
    tc filter add dev "$W" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $IFB &&
    tc qdisc replace dev $IFB root cake $DLBW $DS $FMD $NAT $WASH ingress rtt $RTT $OH $CUSTOM || {
      log "loi ap dung ingress tren $W/$IFB"; clear_qdisc "$W"; return 3; }
  fi
  log "CAKE bat tren $W (down ${DLBW:-unlimited} up ${ULBW:-unlimited}, $DS, $FMU/$FMD, $NAT, $OH)"
  return 0
}

# vong giam sat: ap dung lai khi WAN ket noi lai (PPPoE/DHCP) lam mat qdisc
daemon() {
  fail=0
  while [ "$(g cake_enable 0)" = "1" ]; do
    W=$(get_wan)
    if [ -n "$W" ] && ! is_active "$W"; then
      apply; rc=$?
      case $rc in
        0) fail=0 ;;
        3) fail=$((fail+1)) ;;      # tc loi that su; rc=2 (WAN chua len) khong tinh
      esac
    fi
    # tc loi lien tuc: giam tan suat thu lai de khong lam chap chon mang
    if [ $fail -ge 5 ]; then sleep 120; else sleep 15; fi
  done
}

kill_daemon() { [ -f $PIDF ] && { kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; }; }

sent_pkt() { tc -s qdisc show dev "$1" 2>/dev/null | awk '/^ Sent/{print $4; exit}'; }
ifstat()   { cat "/sys/class/net/$1/statistics/$2" 2>/dev/null || echo 0; }

case "$1" in
  start)
    kill_daemon
    [ "$(g cake_enable 0)" = "1" ] || exit 0
    "$0" daemon >/dev/null 2>&1 &
    echo $! > $PIDF
    ;;
  daemon)  daemon ;;
  stop)
    kill_daemon
    clear_qdisc "$(get_wan)" "$(cat $WANF 2>/dev/null)"
    rm -f $WANF
    log "CAKE da tat"
    ;;
  restart) "$0" stop; "$0" start ;;
  apply)   apply ;;
  status)
    W=$(get_wan)
    echo "enable=$(g cake_enable 0)  wan=$W  daemon=$( [ -f $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null && echo chay || echo dung )"
    echo "hw_nat: module=$(lsmod 2>/dev/null | awk '$1=="hw_nat"{f=1} END{print f?"da nap":"khong"}')  hw_nat_mode=$(g hw_nat_mode '?')  sfe_enable=$(g sfe_enable '?')"
    echo "--- $W (upload) ---";    tc -s qdisc show dev "$W" 2>&1 | head -30
    echo "--- $IFB (download) ---"; tc -s qdisc show dev $IFB 2>&1 | head -30
    ;;
  check)
    # Chay khi DANG tai/speedtest: so goi CAKE xu ly voi goi that tren cong WAN
    W=$(get_wan); [ -n "$W" ] || { echo "Khong tim thay WAN"; exit 1; }
    is_active "$W" || { echo "CAKE chua hoat dong tren $W (xem: cake.sh status)"; exit 1; }
    DL=$(bw "$(g cake_down_bw 0)")
    t1=$(ifstat "$W" tx_packets); r1=$(ifstat "$W" rx_packets)
    u1=$(sent_pkt "$W"); d1=$(sent_pkt $IFB)
    echo "Do trong 5 giay... (hay chay speedtest cung luc)"; sleep 5
    t2=$(ifstat "$W" tx_packets); r2=$(ifstat "$W" rx_packets)
    u2=$(sent_pkt "$W"); d2=$(sent_pkt $IFB)
    dt=$((t2-t1)); dr=$((r2-r1)); du=$(( ${u2:-0}-${u1:-0} )); dd=$(( ${d2:-0}-${d1:-0} ))
    echo "Upload   : WAN tx=$dt goi, CAKE xu ly=$du goi"
    if [ -n "$DL" ]; then echo "Download : WAN rx=$dr goi, CAKE xu ly=$dd goi"; else echo "Download : chua dat gioi han -> khong qua CAKE"; fi
    [ "$dt" -gt 500 ] && [ "$du" -lt $((dt*7/10)) ] && echo "!! Upload: CAKE chi thay $((du*100/dt))% goi -> kha nang HW NAT/offload dang bo qua CAKE"
    [ -n "$DL" ] && [ "$dr" -gt 500 ] && [ "$dd" -lt $((dr*7/10)) ] && echo "!! Download: CAKE chi thay $((dd*100/dr))% goi -> kha nang HW NAT/offload dang bo qua CAKE"
    echo "--- CPU ---"; top -b -n 1 2>/dev/null | head -3
    ;;
  *) echo "Dung: $0 {start|stop|restart|status|apply|check}"; exit 1 ;;
esac
exit 0
