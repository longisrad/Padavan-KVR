#!/bin/sh
# CAKE SQM cho Padavan (MT7621). Cau hinh doc tu nvram (cake_*), do rc goi: restart_cake.
# Dung: cake.sh start|stop|restart|status|apply|check|test
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

# WAN = dev cua default route, bo qua tun/tailscale/wireguard/ifb
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

# ==============================================================================
# GAN NHAN DSCP TU DONG (Game / Voice / Video / Torrent) - chi co tac dung len UPLOAD
# (PREROUTING chay SAU ingress qdisc nen khong anh huong phan loai chieu download).
# Chi hook goi tu LAN (-i br0) de khong ton CPU cho goi download; OUTPUT = goi do router phat.
# ==============================================================================
lan_if() { l=$(nvram get lan_ifname 2>/dev/null); if [ -n "$l" ]; then echo "$l"; else echo br0; fi; }

clean_dscp_rules() {
  L=$(lan_if)
  for T in iptables ip6tables; do
    command -v $T >/dev/null 2>&1 || continue
    while $T -t mangle -D PREROUTING -i "$L" -j CAKE_DSCP 2>/dev/null; do :; done
    while $T -t mangle -D PREROUTING -j CAKE_DSCP 2>/dev/null; do :; done   # ban cu (khong -i)
    while $T -t mangle -D OUTPUT -j CAKE_DSCP 2>/dev/null; do :; done
    $T -t mangle -F CAKE_DSCP 2>/dev/null
    $T -t mangle -X CAKE_DSCP 2>/dev/null
  done
}

dscp_hook_ok() { iptables -t mangle -S PREROUTING 2>/dev/null | grep -q CAKE_DSCP; }

apply_dscp_rules() {
  clean_dscp_rules
  [ "$(g cake_dscp_auto 0)" = "1" ] || return 0
  L=$(lan_if)
  SMALL=$(g cake_dscp_small_udp 0)   # tuy chon: danh dau moi goi UDP <=256B la CS5 (de lam loang lan Voice)

  modprobe xt_DSCP 2>/dev/null || modprobe ipt_DSCP 2>/dev/null
  modprobe xt_multiport 2>/dev/null
  [ "$SMALL" = "1" ] && modprobe xt_length 2>/dev/null

  for T in iptables ip6tables; do
    command -v $T >/dev/null 2>&1 || continue
    if [ "$T" = iptables ]; then ICMP=icmp; else ICMP=ipv6-icmp; fi
    $T -t mangle -N CAKE_DSCP 2>/dev/null || continue
    dr() { $T -t mangle -A CAKE_DSCP "$@" 2>/dev/null; }

    # 1. QUIC/HTTP3 (UDP 443/80): khong gan nhan (tranh YouTube 4K vao lan Voice)
    dr -p udp -m multiport --dports 443,80 -j RETURN
    # 2. CS6: ping, DNS, NTP, TCP SYN
    dr -p $ICMP -j DSCP --set-dscp-class CS6
    dr -p udp -m multiport --dports 53,123 -j DSCP --set-dscp-class CS6
    dr -p tcp --dport 53 -j DSCP --set-dscp-class CS6
    dr -p tcp --syn -j DSCP --set-dscp-class CS6
    # 3. Voice/Game: CS5 / EF
    dr -p udp -m multiport --dports 3478,5349,19302:19309 -j DSCP --set-dscp-class CS5
    dr -p udp -m multiport --dports 5060,5061 -j DSCP --set-dscp-class EF
    dr -p udp -m multiport --dports 27000:27100,5000:5500,7000:8000,8393:8400,10000:10100 -j DSCP --set-dscp-class CS5
    if [ "$SMALL" = "1" ]; then
      # target DSCP khong ket thuc chain: giu nguyen nhan DNS/NTP/SIP da gan o tren
      dr -p udp -m multiport --dports 53,123,5060,5061 -j RETURN
      dr -p udp -m length --length :256 -j DSCP --set-dscp-class CS5
    fi
    # 4. Video/Livestream: CS4
    dr -p tcp --dport 1935 -j DSCP --set-dscp-class CS4
    dr -p udp -m multiport --dports 8801:8810 -j DSCP --set-dscp-class CS4
    dr -p tcp -m multiport --dports 8801:8810 -j DSCP --set-dscp-class CS4
    # 5. Torrent/P2P: CS1 (Bulk)
    dr -p tcp -m multiport --dports 6881:6889 -j DSCP --set-dscp-class CS1
    dr -p udp -m multiport --dports 6881:6889 -j DSCP --set-dscp-class CS1

    $T -t mangle -A PREROUTING -i "$L" -j CAKE_DSCP 2>/dev/null
    $T -t mangle -A OUTPUT -j CAKE_DSCP 2>/dev/null
  done

  N=$(iptables -t mangle -S CAKE_DSCP 2>/dev/null | grep -c -- '-j DSCP')
  if [ "$N" -gt 0 ] && dscp_hook_ok; then
    log "DSCP tự động: $N luật IPv4 (LAN=$L, small_udp=$SMALL)"
  else
    log "DSCP tự động: KHÔNG gắn được luật (thiếu xt_DSCP hoặc iptables không hỗ trợ DSCP?)"
  fi
}

# CAKE con hieu luc tren WAN $1 khong
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
  case "$FM" in
    auto)
      if [ "$NAT" = nat ]; then FMU=dual-srchost; FMD=dual-dsthost; else FMU=triple-isolate; FMD=triple-isolate; fi ;;
    dual-srchost|dual-dsthost) FMU=dual-srchost; FMD=dual-dsthost ;;
    srchost|dsthost)           FMU=srchost;      FMD=dsthost ;;
    triple-isolate)
      # Upload: triple-isolate. Download: flowblind (nhe CPU nhung KHONG chia deu theo may/luong
      # o chieu tai ve). Muon chia deu ca hai chieu: dung triple-isolate-both hoac auto.
      FMU=triple-isolate; FMD=flowblind ;;
    triple-isolate-both) FMU=triple-isolate; FMD=triple-isolate ;;
    flowblind|hosts|flows) FMU=$FM; FMD=$FM ;;
    *) FMU=triple-isolate; FMD=flowblind ;;
  esac
  # flowblind khong dung thong tin host -> "nat" chi ton them tra cuu conntrack moi goi: tat theo tung chieu
  NATU=$NAT; NATD=$NAT
  [ "$FMU" = flowblind ] && NATU=nonat
  [ "$FMD" = flowblind ] && NATD=nonat
  DS=$(g cake_diffserv diffserv3)
  case "$DS" in besteffort|diffserv3|diffserv4|diffserv8) ;; *) DS=diffserv3 ;; esac
  RTT=$(g cake_rtt internet)
  case "$RTT" in datacentre|lan|metro|regional|internet|oceanic|satellite) ;; *) RTT=internet ;; esac
  OH=$(g cake_overhead ethernet)
  case "$OH" in raw|ethernet|ether-vlan|pppoe-ptm|bridged-ptm|docsis|conservative) ;; *) OH=ethernet ;; esac
  case "$(g cake_ack_filter none)" in ack-filter) AF="ack-filter" ;; ack-filter-aggressive) AF="ack-filter-aggressive" ;; *) AF="" ;; esac
  [ "$(g cake_wash 0)" = "1" ] && WASH=wash || WASH=""
  CUSTOM=$(g cake_custom ""); [ -z "$(printf %s "$CUSTOM" | tr -d 'A-Za-z0-9 ._-')" ] || CUSTOM=""

  W=$(get_wan)
  [ -n "$W" ] && ip link show "$W" >/dev/null 2>&1 || return 2

  OLD=$(cat $WANF 2>/dev/null)
  [ -n "$OLD" ] && [ "$OLD" != "$W" ] && clear_qdisc "$OLD"
  clear_qdisc "$W"
  echo "$W" > $WANF

  [ -z "$DLBW" ] && [ -z "$ULBW" ] && log "chưa đặt tốc độ up/down: CAKE chỉ chia luồng, không giảm bufferbloat"

  # Upload (egress trên WAN)
  ERR=$(tc qdisc replace dev "$W" root cake $ULBW $DS $FMU $NATU nowash $RTT $OH $AF $CUSTOM 2>&1) || {
    log "lỗi áp dụng egress trên $W: $ERR | lệnh: cake $ULBW $DS $FMU $NATU nowash $RTT $OH $AF $CUSTOM"
    clear_qdisc "$W"; return 3; }

  # Download (ingress -> ifb0)
  if [ -n "$DLBW" ]; then
    ip link show $IFB >/dev/null 2>&1 || ip link add $IFB type ifb 2>/dev/null
    ip link set $IFB up
    ERR=$(tc qdisc add dev "$W" handle ffff: ingress 2>&1 &&
          tc filter add dev "$W" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $IFB 2>&1 &&
          tc qdisc replace dev $IFB root cake $DLBW $DS $FMD $NATD $WASH ingress $RTT $OH $CUSTOM 2>&1) || {
      log "lỗi áp dụng ingress trên $W/$IFB: $ERR"; clear_qdisc "$W"; return 3; }
  fi

  # Kích hoạt luật DSCP Mangle nếu bật tùy chọn
  apply_dscp_rules

  log "CAKE bật trên $W (down ${DLBW:-unlimited} up ${ULBW:-unlimited}, $DS, $FMU/$FMD, nat=$NATU/$NATD, $OH, dscp_auto=$(g cake_dscp_auto 0))"
  return 0
}

daemon() {
  fail=0
  while [ "$(g cake_enable 0)" = "1" ]; do
    W=$(get_wan)
    if [ -n "$W" ] && ! is_active "$W"; then
      apply; rc=$?
      case $rc in
        0) fail=0 ;;
        3) fail=$((fail+1)) ;;
      esac
    elif [ "$(g cake_dscp_auto 0)" = "1" ] && ! dscp_hook_ok; then
      apply_dscp_rules   # firewall restart (WAN len/xuong) xoa chain mangle -> gan lai
    fi
    if [ $fail -ge 5 ]; then sleep 120; else sleep 15; fi
  done
}

# chi kill/nhan dien dung tien trinh cake.sh (tranh PID bi tai su dung)
daemon_alive() {
  p=$(cat $PIDF 2>/dev/null); [ -n "$p" ] || return 1
  tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q "cake.sh"
}
kill_daemon() {
  daemon_alive && kill "$(cat $PIDF)" 2>/dev/null
  rm -f $PIDF
}
sent_pkt()    { tc -s qdisc show dev "$1" 2>/dev/null | awk '/^ Sent/{print $4; exit}'; }
ifstat()      { cat "/sys/class/net/$1/statistics/$2" 2>/dev/null || echo 0; }
# usr(user+nice) sys idle io irq sirq
cpu_snap()    { awk '/^cpu /{print $2+$3, $4, $5, $6, $7, $8}' /proc/stat; }

# khoi so lieu may doc duoc cho trang web (moi dong: khoa=gia tri)
stats_block() {
  echo "--- stats ---"
  echo "up=$(cut -d' ' -f1 /proc/uptime)"
  echo "wan_rx_packets=$(ifstat "$1" rx_packets)"
  echo "wan_tx_packets=$(ifstat "$1" tx_packets)"
  echo "wan_rx_bytes=$(ifstat "$1" rx_bytes)"
  echo "wan_tx_bytes=$(ifstat "$1" tx_bytes)"
  echo "cpu=$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)"
  echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
  echo "tmp_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2{print $2" "$3}')"
  echo "memfree_kb=$(awk '/^MemFree:/{print $2}' /proc/meminfo)"
  echo "dscp_hook=$(dscp_hook_ok && echo ok || echo no)"
}

case "$1" in
  start)
    kill_daemon
    [ "$(g cake_enable 0)" = "1" ] || exit 0
    sh "$0" daemon >/dev/null 2>&1 &
    echo $! > $PIDF
    ;;
  daemon) daemon ;;
  stop)
    kill_daemon
    clean_dscp_rules
    clear_qdisc "$(get_wan)" "$(cat $WANF 2>/dev/null)"
    rm -f $WANF
    log "CAKE đã tắt"
    ;;
  restart) sh "$0" stop; sh "$0" start ;;
  apply)   apply ;;
  status)
    W=$(get_wan)
    echo "enable=$(g cake_enable 0)  wan=$W  daemon=$(daemon_alive && echo chay || echo dung)  dscp_auto=$(g cake_dscp_auto 0)"
    echo "hw_nat: module=$(lsmod 2>/dev/null | awk '$1=="hw_nat"{f=1} END{print f?"da nap":"khong"}')  hw_nat_mode=$(g hw_nat_mode '?')  sfe_enable=$(g sfe_enable '?')"
    echo "--- $W (upload) ---";    tc -s qdisc show dev "$W" 2>&1 | head -60
    echo "--- $IFB (download) ---"; tc -s qdisc show dev $IFB 2>&1 | head -60
    stats_block "$W"
    ;;
  check)
    W=$(get_wan); [ -n "$W" ] || { echo "Không tìm thấy WAN"; exit 1; }
    is_active "$W" || { echo "CAKE chưa hoạt động trên $W (xem: cake.sh status)"; exit 1; }
    DL=$(bw "$(g cake_down_bw 0)")
    t1=$(ifstat "$W" tx_packets); r1=$(ifstat "$W" rx_packets)
    u1=$(sent_pkt "$W"); d1=$(sent_pkt $IFB); c1=$(cpu_snap)
    echo "Đo trong 5 giây... (hãy chạy speedtest cùng lúc)"; sleep 5
    t2=$(ifstat "$W" tx_packets); r2=$(ifstat "$W" rx_packets)
    u2=$(sent_pkt "$W"); d2=$(sent_pkt $IFB); c2=$(cpu_snap)
    dt=$((t2-t1)); dr=$((r2-r1)); du=$(( ${u2:-0}-${u1:-0} )); dd=$(( ${d2:-0}-${d1:-0} ))
    echo "Upload   : WAN tx=$dt gói, CAKE xử lý=$du gói"
    if [ -n "$DL" ]; then echo "Download : WAN rx=$dr gói, CAKE xử lý=$dd gói"; else echo "Download : chưa đặt giới hạn -> không qua CAKE"; fi
    [ "$dt" -gt 500 ] && [ "$du" -lt $((dt*7/10)) ] && echo "!! Upload: CAKE chỉ thấy $((du*100/dt))% gói -> có thể HW NAT đang bỏ qua CAKE"
    [ -n "$DL" ] && [ "$dr" -gt 500 ] && [ "$dd" -lt $((dr*7/10)) ] && echo "!! Download: CAKE chỉ thấy $((dd*100/dr))% gói -> có thể HW NAT đang bỏ qua CAKE"
    echo "--- CPU (trung bình 5 giây vừa đo) ---"
    echo "$c1 $c2" | awk '{ for(i=1;i<=6;i++){d[i]=$(i+6)-$i; t+=d[i]} if(t>0) printf "usr %.0f%%  sys %.0f%%  irq %.0f%%  sirq %.0f%%  io %.0f%%  idle %.0f%%\n", d[1]*100/t, d[2]*100/t, d[5]*100/t, d[6]*100/t, d[4]*100/t, d[3]*100/t }'
    echo "--- DSCP hook: $(dscp_hook_ok && echo ok || echo khong co) ---"
    ;;
  test)
    kill_daemon; W=${2:-$(get_wan)}; clear_qdisc "$W"
    [ -n "$W" ] || { echo "Không tìm thấy WAN"; exit 1; }
    echo "dev=$W"; ip link show "$W" 2>&1 | head -2
    try() {
      printf '%-62s' "cake $*"
      out=$(tc qdisc replace dev "$W" root cake "$@" 2>&1) && echo "OK" || echo "LỖI: $out"
      tc qdisc del dev "$W" root 2>/dev/null
    }
    try
    try bandwidth 100mbit
    try bandwidth 100mbit diffserv3
    try bandwidth 100mbit besteffort
    try bandwidth 100mbit triple-isolate
    try bandwidth 100mbit dual-srchost
    try bandwidth 100mbit nat
    try bandwidth 100mbit nowash
    try bandwidth 100mbit internet
    try bandwidth 100mbit rtt 100ms
    try bandwidth 100mbit ethernet
    try bandwidth 100mbit ack-filter
    echo "--- ifb0 ---"
    ip link show $IFB >/dev/null 2>&1 || ip link add $IFB type ifb 2>&1
    ip link set $IFB up 2>&1
    out=$(tc qdisc replace dev $IFB root cake bandwidth 100mbit ingress 2>&1) && echo "cake ingress trên $IFB: OK" || echo "cake ingress trên $IFB: LỖI: $out"
    tc qdisc del dev $IFB root 2>/dev/null
    echo "Xong. Bật lại CAKE: $0 restart"
    ;;
  *) echo "Dùng: $0 {start|stop|restart|status|apply|check|test [dev]}"; exit 1 ;;
esac
exit 0
