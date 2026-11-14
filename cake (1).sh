#!/bin/sh
# CAKE SQM cho Padavan (MT7621). Cau hinh doc tu nvram (cake_*), do rc goi: restart_cake.
# Dung: cake.sh start|stop|restart|status|apply|reset|check|dscp|test
PIDF=/var/run/cake.pid
WANF=/var/run/cake.wan
EPOCHF=/var/run/cake.epoch   # uptime (giay) luc qdisc CAKE duoc tao lan cuoi = moc bo dem ve 0
IFB=ifb0
SIGF=/var/run/cake.sig       # "chu ky" cau hinh (nvram cake_* + WAN) tai lan apply thanh cong gan nhat
LOCKD=/var/run/cake.lock     # khoa (thu muc) de start/stop/apply/daemon khong chay chong nhau
TRACEF=/tmp/cake.trace       # nhat ky ngan (RAM) co moc uptime + pid, xem bang: cake.sh diag
SIGKEYS="cake_enable cake_down_bw cake_up_bw cake_flow_mode cake_diffserv cake_rtt cake_overhead cake_ack_filter cake_nat cake_wash cake_dscp_auto cake_dscp_small_udp cake_custom"

g()   { v=$(nvram get "$1" 2>/dev/null); if [ -n "$v" ]; then echo "$v"; else echo "$2"; fi; }
trace() {
  echo "$(cut -d' ' -f1 /proc/uptime) [$$] $*" >> $TRACEF 2>/dev/null
  set -- $(wc -l < $TRACEF 2>/dev/null)
  [ "${1:-0}" -gt 300 ] && { tail -n 150 $TRACEF > $TRACEF.t 2>/dev/null && mv $TRACEF.t $TRACEF; }
  return 0
}
log() { logger -t cake "$*" 2>/dev/null; trace "$*"; }

# ---- KHOA: mkdir nguyen tu; chu khoa chet thi tu don sau ~2 giay ----
lock_owner_alive() {
  lp=$(cat $LOCKD/pid 2>/dev/null); [ -n "$lp" ] || return 1
  tr '\0' ' ' 2>/dev/null < /proc/$lp/cmdline | grep -q "cake.sh"
}
lock_acquire() {   # lock_acquire <so giay toi da>
  lt=${1:-30}; li=0; ld=0
  while ! mkdir $LOCKD 2>/dev/null; do
    if lock_owner_alive; then ld=0
    else ld=$((ld+1)); [ $ld -ge 3 ] && { rm -rf $LOCKD; ld=0; continue; }
    fi
    li=$((li+1)); [ $li -ge $lt ] && return 1
    sleep 1
  done
  echo $$ > $LOCKD/pid
  return 0
}
lock_release() { [ "$(cat $LOCKD/pid 2>/dev/null)" = "$$" ] && rm -rf $LOCKD; return 0; }
# with_lock <giay> lenh...: 99 = khong lay duoc khoa (bo qua luot nay)
with_lock() {
  wt=$1; shift
  lock_acquire "$wt" || return 99
  "$@"; wr=$?
  lock_release
  return $wr
}
# lenh nguoi dung/rc goi: giu khoa suot lenh, tu nha khi thoat
run_locked() {
  lock_acquire 30 || { log "không lấy được khóa (lệnh $1): có tiến trình cake.sh khác đang chạy quá lâu"; echo "cake.sh: không lấy được khóa"; exit 1; }
  trap lock_release EXIT
  trace "lệnh $1 (ppid=$PPID)"
}

# chu ky cau hinh = WAN + cac gia tri nvram cake_* anh huong CAKE
cfg_sig() { cs="$1"; for k in $SIGKEYS; do cs="$cs|$(g $k '')"; done; echo "$cs"; }

# cac tien trinh daemon/fbdaemon (bo qua tien trinh con sinh ra tu chinh daemon)
list_daemons() {
  for d in /proc/[0-9]*; do
    lp=${d#/proc/}; [ "$lp" = "$$" ] && continue
    tr '\0' ' ' 2>/dev/null < $d/cmdline | grep -Eq '^(/bin/)?sh [^ ]*cake\.sh (daemon|fbdaemon) *$' || continue
    pp=$(awk '/^PPid:/{print $2}' $d/status 2>/dev/null)
    tr '\0' ' ' 2>/dev/null < /proc/$pp/cmdline | grep -Eq '^(/bin/)?sh [^ ]*cake\.sh (daemon|fbdaemon) *$' && continue
    echo $lp
  done
}

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

# ==============================================================================
# DU PHONG khi CAKE tat hoac loi lien tuc. Chon loai: nvram set cake_fb_qdisc=auto|fq_codel|sfq|off
#   (tat han: cake_fb_qdisc=off hoac cake_fallback=0)
#   - co cake_up_bw / cake_down_bw: HTB (dat toc do) + fq_codel (neu kernel thieu thi sfq)
#   - khong co toc do: fq_codel (hoac sfq) tren WAN, khong gioi han
#   - khong co ca hai: de nguyen pfifo_fast
# HTB khong tinh overhead lop 2 -> tru ~5% toc do de bu (1514/1552)
# ==============================================================================
# in gia tri nvram $1 neu la so > 0, nguoc lai in rong
bwn() {
  v=$(g "$1" 0)
  echo "$v" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || return 0
  awk -v x="$v" 'BEGIN{exit !(x+0>0)}' && echo "$v"
}
# Che do du phong (nvram cake_fb_qdisc): auto = fq_codel roi sfq | fq_codel | sfq | off = khong du phong
# cake_fallback=0 (cu) van tat han du phong
fb_mode() {
  [ "$(g cake_fallback 1)" = "1" ] || { echo off; return; }
  case "$(g cake_fb_qdisc auto)" in
    fq_codel) echo fq_codel ;; sfq) echo sfq ;; off) echo off ;; *) echo auto ;;
  esac
}
fb_on() { [ "$(fb_mode)" != "off" ]; }
# fb_add <dev> <vi tri tc: root | parent 1:10 handle 10:> : gan qdisc theo che do da chon
#   sfq      : chi sfq
#   fq_codel : fq_codel, kernel thieu thi tu quay ve sfq
#   auto     : fq_codel truoc, thieu thi sfq
fb_add() {
  d=$1; shift
  if [ "$(fb_mode)" != "sfq" ]; then
    tc qdisc replace dev "$d" "$@" fq_codel limit 1024 2>/dev/null && return 0
  fi
  tc qdisc replace dev "$d" "$@" sfq perturb 10 2>/dev/null
}
# leaf cua HTB (that bai ca hai thi htb tu dung pfifo)
fb_leaf() { fb_add "$1" parent 1:10 handle 10:; }
# fb_htb <dev> <Mbit>: 0 = xong, 1 = khong dat duoc (kernel thieu htb...)
fb_htb() {
  K=$(awk -v x="$2" 'BEGIN{printf "%d", x*950}')
  [ "${K:-0}" -gt 0 ] || return 1
  tc qdisc replace dev "$1" root handle 1: htb default 10 2>/dev/null || return 1
  tc class replace dev "$1" parent 1: classid 1:10 htb rate ${K}kbit ceil ${K}kbit quantum 1514 2>/dev/null || {
    tc qdisc del dev "$1" root 2>/dev/null; return 1; }
  fb_leaf "$1"
  return 0
}
# du phong con hieu luc tren WAN $1 khong
fb_active() { tc qdisc show dev "$1" 2>/dev/null | grep -Eq 'qdisc (htb|fq_codel|sfq) '; }

fallback_qdisc() {
  fb_on || return 0
  W=$(get_wan); [ -n "$W" ] && ip link show "$W" >/dev/null 2>&1 || return 0
  clear_qdisc "$W"
  UP=$(bwn cake_up_bw); DN=$(bwn cake_down_bw); M=""
  if [ -n "$UP" ] && fb_htb "$W" "$UP"; then
    M="htb ${UP}M + $(tc qdisc show dev "$W" 2>/dev/null | awk '/^qdisc (fq_codel|sfq) /{print $2; exit}')"
  elif fb_add "$W" root; then
    M=$(tc qdisc show dev "$W" 2>/dev/null | awk '/^qdisc/{print $2; exit}')
  else return 0; fi
  if [ -n "$DN" ]; then
    ip link show $IFB >/dev/null 2>&1 || ip link add $IFB type ifb 2>/dev/null
    ip link set $IFB up 2>/dev/null
    if tc qdisc add dev "$W" handle ffff: ingress 2>/dev/null &&
       tc filter add dev "$W" parent ffff: protocol all u32 match u32 0 0 action mirred egress redirect dev $IFB 2>/dev/null &&
       fb_htb $IFB "$DN"; then
      M="$M, down htb ${DN}M"
    else
      tc qdisc del dev "$W" ingress 2>/dev/null; tc qdisc del dev $IFB root 2>/dev/null
    fi
  fi
  echo "$W" > $WANF
  log "Dự phòng ($M) trên $W"
}
# CAKE tat: giu du phong khi WAN noi lai (firewall/ppp lam mat qdisc), ~30 giay/lan
fbdaemon() {
  while [ "$(g cake_enable 0)" != "1" ] && fb_on; do
    W=$(get_wan)
    [ -n "$W" ] && ! fb_active "$W" && with_lock 20 fallback_qdisc
    sleep 30
  done
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
# iptables/ip6tables co chay duoc khong (khong dung `command -v`: ash cua firmware co the thieu builtin nay)
have() { "$1" -V >/dev/null 2>&1; }
lan_if() { l=$(nvram get lan_ifname 2>/dev/null); if [ -n "$l" ]; then echo "$l"; else echo br0; fi; }

clean_dscp_rules() {
  for T in iptables ip6tables; do
    have $T || continue
    # go moi tham chieu toi CAKE_DSCP (ke ca ban cu co the khac -i/-o), neu khong -X se that bai
    for CH in PREROUTING OUTPUT; do
      $T -t mangle -S $CH 2>/dev/null | grep -- '-j CAKE_DSCP' | sed 's/^-A/-D/' | while read -r r; do
        $T -t mangle $r 2>/dev/null
      done
    done
    # du phong neu iptables khong ho tro -S: go theo cac dang da tung dung
    LL=$(lan_if)
    while $T -t mangle -D PREROUTING -i "$LL" -j CAKE_DSCP 2>/dev/null; do :; done
    while $T -t mangle -D PREROUTING -j CAKE_DSCP 2>/dev/null; do :; done
    while $T -t mangle -D OUTPUT -j CAKE_DSCP 2>/dev/null; do :; done
    $T -t mangle -F CAKE_DSCP 2>/dev/null
    $T -t mangle -X CAKE_DSCP 2>/dev/null
  done
}

# dem luat DSCP trong chain (thu -S, neu 0 thu -L de tuong thich iptables cu)
dscp_count() {
  n=$(iptables -t mangle -S CAKE_DSCP 2>/dev/null | grep -c -- '-j DSCP')
  [ "$n" -gt 0 ] || n=$(iptables -t mangle -nL CAKE_DSCP 2>/dev/null | grep -c '^DSCP ')
  echo "$n"
}
dscp_hook_ok() {
  if ! iptables -t mangle -S PREROUTING 2>/dev/null | grep -q -- '-j CAKE_DSCP'; then
    iptables -t mangle -nL PREROUTING 2>/dev/null | grep -q '^CAKE_DSCP ' || return 1
  fi
  [ "${1:-$(dscp_count)}" -gt 0 ]
}

# Co can gan DSCP khong: bat tuy chon VA diffserv khac besteffort
# (besteffort bo qua hoan toan nhan DSCP -> luat chi ton CPU vo ich)
dscp_wanted() {
  [ "$(g cake_dscp_auto 0)" = "1" ] || return 1
  [ "$(g cake_diffserv diffserv3)" != "besteffort" ]
}

# BANG NHAN DSCP (chi tac dung chieu UPLOAD) - chon nhan dung voi bang phan lan cua CAKE:
#   CS6  : ping, DNS, NTP, TCP SYN        -> lan Voice (diffserv3/4)
#   EF   : SIP/VoIP/WebRTC (STUN,TURN), Game -> lan Voice o MOI che do diffserv
#          (CS5/CS4 chi vao Voice o diffserv4; o diffserv3 roi vao Best Effort nen khong con tac dung)
#   AF41 : Livestream/Zoom                -> lan Video o diffserv4 (diffserv3: Best Effort, khong chiem uu tien)
#   CS1  : Torrent/P2P                    -> lan Bulk
apply_dscp_rules() {
  clean_dscp_rules
  if [ "$(g cake_dscp_auto 0)" = "1" ] && ! dscp_wanted; then
    log "DSCP tự động: bỏ qua vì diffserv=besteffort (CAKE không phân làn theo DSCP)"
  fi
  dscp_wanted || return 0
  L=$(lan_if)
  SMALL=$(g cake_dscp_small_udp 0)   # tuy chon: danh dau moi goi UDP <=256B la EF (de lam loang lan Voice)
  # Chi xu ly goi LAN -> ra ngoai: bo qua goi dich la mang LAN (DNS toi router, LAN-LAN...) cho do ton CPU
  LCIDR=$(ip -4 -o addr show dev "$L" 2>/dev/null | awk '{print $4; exit}')
  HOOK_DST=""; [ -n "$LCIDR" ] && HOOK_DST="! -d $LCIDR"

  modprobe xt_DSCP 2>/dev/null || modprobe ipt_DSCP 2>/dev/null
  modprobe xt_multiport 2>/dev/null
  modprobe xt_length 2>/dev/null
  ERR4=""; NOLEN=0

  for T in iptables ip6tables; do
    have $T || continue
    if [ "$T" = iptables ]; then ICMP=icmp; else ICMP=ipv6-icmp; fi
    e=$($T -t mangle -N CAKE_DSCP 2>&1) || { [ "$T" = iptables ] && ERR4="-N CAKE_DSCP: $e"; continue; }
    # luat dau tien that bai (IPv4) duoc ghi vao ERR4 de dua ra log
    dr() { e=$($T -t mangle -A CAKE_DSCP "$@" 2>&1) && return 0; [ "$T" = iptables ] && [ -z "$ERR4" ] && ERR4="$* => $e"; return 1; }

    # 1. THOAT SOM cho luu luong pho bien nhat (HTTPS/HTTP): khong luat nao ben duoi can gan nhan cho
    #    goi du lieu/ACK toi cong 443/80 -> bo qua ~12 luat con lai cho phan lon goi upload.
    #    TCP SYN van di tiep xuong (de nhan CS6). UDP 443/80 = QUIC/HTTP3: khong gan nhan
    #    (tranh YouTube 4K / tai len QUIC vao lan Voice).
    dr -p tcp ! --syn -m multiport --dports 443,80 -j RETURN
    dr -p udp -m multiport --dports 443,80 -j RETURN
    # 2. CS6: ping, DNS, NTP, TCP SYN
    dr -p $ICMP -j DSCP --set-dscp-class CS6
    dr -p udp -m multiport --dports 53,123 -j DSCP --set-dscp-class CS6
    dr -p tcp --dport 53 -j DSCP --set-dscp-class CS6
    dr -p tcp --syn -j DSCP --set-dscp-class CS6
    # 3. Voice/WebRTC/SIP: EF
    dr -p udp -m multiport --dports 3478,5349,19302:19309 -j DSCP --set-dscp-class EF
    dr -p udp -m multiport --dports 5060,5061 -j DSCP --set-dscp-class EF
    # 3b. Game: dai cong rong nen CHI nhan goi UDP nho (<=400B). Goi lon (uTP/P2P, tai du lieu)
    #     khong lot vao lan Voice. Thieu xt_length thi quay ve luat khong loc co goi.
    GP="27000:27100,5000:5500,7000:8000,8393:8400,10000:10100"
    if ! dr -p udp -m multiport --dports $GP -m length --length :400 -j DSCP --set-dscp-class EF; then
      [ "$T" = iptables ] && NOLEN=1
      dr -p udp -m multiport --dports $GP -j DSCP --set-dscp-class EF
    fi
    if [ "$SMALL" = "1" ]; then
      # target DSCP khong ket thuc chain: giu nguyen nhan DNS/NTP/SIP da gan o tren
      dr -p udp -m multiport --dports 53,123,5060,5061 -j RETURN
      dr -p udp -m length --length :256 -j DSCP --set-dscp-class EF
    fi
    # 4. Video/Livestream: AF41 (lan Video cua diffserv4)
    dr -p tcp --dport 1935 -j DSCP --set-dscp-class AF41
    dr -p udp -m multiport --dports 8801:8810 -j DSCP --set-dscp-class AF41
    dr -p tcp -m multiport --dports 8801:8810 -j DSCP --set-dscp-class AF41
    # 5. Torrent/P2P: CS1 (Bulk)
    dr -p tcp -m multiport --dports 6881:6889 -j DSCP --set-dscp-class CS1
    dr -p udp -m multiport --dports 6881:6889 -j DSCP --set-dscp-class CS1

    if [ "$T" = iptables ]; then HD="$HOOK_DST"; else HD=""; fi
    e=$($T -t mangle -A PREROUTING -i "$L" $HD -j CAKE_DSCP 2>&1) || { [ "$T" = iptables ] && ERR4="hook PREROUTING -i $L => $e"; }
    # OUTPUT: chi goi router tu phat ra ngoai (khong tinh goi tra loi cho LAN)
    $T -t mangle -A OUTPUT ! -o "$L" -j CAKE_DSCP 2>/dev/null
  done

  N=$(dscp_count)
  if [ "$N" -gt 0 ] && dscp_hook_ok; then
    log "DSCP tự động: $N luật IPv4 (LAN=$L, small_udp=$SMALL, loại trừ đích=${LCIDR:-không})"
    [ "$NOLEN" = "1" ] && log "DSCP: thiếu module xt_length, dải cổng game không lọc theo cỡ gói (kém chính xác hơn)"
    return 0
  fi
  RAW=$(iptables -t mangle -nL CAKE_DSCP 2>&1 | head -4 | tr '\n' '|')
  log "DSCP tự động: KHÔNG gắn được luật (đếm được $N luật) - lỗi đầu tiên: ${ERR4:-không có thông báo lỗi} - chain: ${RAW:-trống}"
  clean_dscp_rules   # khong de lai hook/chain rong, tranh ton CPU vo ich
  return 1
}

# Neu CAKE CHUA dung nhu cau hinh tren WAN $1 -> in ly do (rong = dung). Kiem ca chu ky cau hinh,
# nen thay doi nvram / lan apply do dang se bi phat hien (khong chi hoi "co qdisc cake hay khong").
why_inactive() {
  Q=$(tc qdisc show dev "$1" 2>/dev/null)
  echo "$Q" | grep -q "qdisc cake" || { echo "WAN $1 không có qdisc cake"; return; }
  if [ -n "$(bw "$(g cake_down_bw 0)")" ]; then
    tc qdisc show dev $IFB 2>/dev/null | grep -q "qdisc cake" || { echo "$IFB không có qdisc cake (tải xuống đang đặt giới hạn)"; return; }
    tc filter show dev "$1" parent ffff: 2>/dev/null | grep -q "$IFB" || { echo "thiếu filter ingress -> $IFB"; return; }
  else
    echo "$Q" | grep -q "qdisc ingress" && { echo "còn ingress thừa trên $1 dù tải xuống = không giới hạn"; return; }
  fi
  [ "$(cat $SIGF 2>/dev/null)" = "$(cfg_sig "$1")" ] || echo "cấu hình đã đổi so với lần áp dụng cuối (hoặc lần áp dụng trước dở dang)"
}
is_active() { [ -z "$(why_inactive "$1")" ]; }

apply() {
  [ "$(g cake_enable 0)" = "1" ] || return 1
  rm -f $SIGF          # lan apply dang do chua xong thi KHONG duoc coi la hop le
  trace "apply: bắt đầu"

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
  # Download (ingress): luon besteffort. Nhan DSCP tu internet khong dang tin (ISP thuong xoa het),
  # phan lan theo DSCP o chieu nay chi ton CPU va cho phep ben ngoai tu nhan uu tien.
  # Muon theo diffserv nhu upload: doi thanh DSD=$DS
  DSD=besteffort
  RTT=$(g cake_rtt internet)
  case "$RTT" in datacentre|lan|metro|regional|internet|oceanic|satellite) ;; *) RTT=internet ;; esac
  OH=$(g cake_overhead ethernet)
  case "$OH" in raw|ethernet|ether-vlan|pppoe-ptm|bridged-ptm|docsis|conservative) ;; *) OH=ethernet ;; esac
  case "$(g cake_ack_filter none)" in ack-filter) AF="ack-filter" ;; ack-filter-aggressive) AF="ack-filter-aggressive" ;; *) AF="" ;; esac
  [ "$(g cake_wash 0)" = "1" ] && WASH=wash || WASH=""
  CUSTOM=$(g cake_custom ""); [ -z "$(printf %s "$CUSTOM" | tr -d 'A-Za-z0-9 ._-')" ] || CUSTOM=""

  W=$(get_wan)
  [ -n "$W" ] && ip link show "$W" >/dev/null 2>&1 || return 2

  # PPPoE: CAKE dat tren ppp* chi thay goi IP, thieu them 8 byte PPPoE/PPP so voi "ethernet" (38)
  case "$W" in ppp*) [ "$OH" = ethernet ] && OH="overhead 46 mpu 84" ;; esac

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
          tc qdisc replace dev $IFB root cake $DLBW $DSD $FMD $NATD $WASH ingress $RTT $OH $CUSTOM 2>&1) || {
      log "lỗi áp dụng ingress trên $W/$IFB: $ERR"; clear_qdisc "$W"; return 3; }
  fi

  # Kích hoạt luật DSCP Mangle nếu bật tùy chọn
  apply_dscp_rules

  cut -d' ' -f1 /proc/uptime > $EPOCHF 2>/dev/null
  cfg_sig "$W" > $SIGF 2>/dev/null
  log "CAKE bật trên $W (down ${DLBW:-unlimited} up ${ULBW:-unlimited}, up=$DS down=$DSD, $FMU/$FMD, nat=$NATU/$NATD, $OH, dscp_auto=$(g cake_dscp_auto 0))"
  # tu kiem tra ngay sau khi ap dung: neu thieu gi thi ghi log de lan sau biet
  why=$(why_inactive "$W"); [ -n "$why" ] && log "sau apply vẫn lệch: $why"
  return 0
}

daemon() {
  fail=0; dtick=0; dfail=0; rtick=0
  while [ "$(g cake_enable 0)" = "1" ]; do
    W=$(get_wan); ran=0; skip=0
    # dang chay du phong sau >=3 lan loi: apply() se go du phong truoc khi thu CAKE -> chi thu lai 1/4 vong
    if [ $fail -ge 3 ] && [ -n "$W" ] && fb_active "$W"; then
      rtick=$((rtick+1)); [ $((rtick % 4)) -eq 0 ] || skip=1
    fi
    if [ -n "$W" ] && [ $skip -eq 0 ]; then
      why=$(why_inactive "$W")
      if [ -n "$why" ]; then
        log "daemon: áp dụng lại CAKE vì: $why"
        with_lock 20 apply; rc=$?; ran=1
        case $rc in
          0) fail=0; rtick=0 ;;
          3) fail=$((fail+1)); [ $fail -ge 3 ] && with_lock 20 fallback_qdisc ;;
          99) trace "daemon: bận khóa, thử lại vòng sau" ;;
        esac
      fi
    fi
    if dscp_wanted && [ $ran -eq 0 ]; then
      if dscp_hook_ok; then
        dtick=0; dfail=0
      else
        # firewall restart (WAN len/xuong) xoa chain mangle -> gan lai.
        # that bai >=3 lan lien tiep (vd thieu module xt_DSCP) -> chi thu lai ~5 phut/lan
        dtick=$((dtick+1))
        if [ $dfail -lt 3 ] || [ $((dtick % 20)) -eq 0 ]; then
          with_lock 20 apply_dscp_rules && dfail=0 || dfail=$((dfail+1))
        fi
      fi
    fi
    if [ $fail -ge 5 ]; then sleep 120; else sleep 15; fi
  done
}

# chi kill/nhan dien dung tien trinh cake.sh (tranh PID bi tai su dung)
daemon_alive() {
  p=$(cat $PIDF 2>/dev/null); [ -n "$p" ] || return 1
  tr '\0' ' ' 2>/dev/null < /proc/$p/cmdline | grep -q "cake.sh"
}
kill_daemon() {
  keep=""; daemon_alive && keep=$(cat $PIDF)
  [ -n "$keep" ] && kill "$keep" 2>/dev/null
  # daemon thua (file pid mat/ghi de) cung bi dung, tranh 2 daemon cung sua qdisc
  for p in $(list_daemons); do
    [ "$p" = "$keep" ] && continue
    kill "$p" 2>/dev/null; log "đã dừng daemon thừa pid=$p"
  done
  rm -f $PIDF
}
sent_pkt()    { tc -s qdisc show dev "$1" 2>/dev/null | awk '/^ Sent/{print $4; exit}'; }
ifstat()      { cat "/sys/class/net/$1/statistics/$2" 2>/dev/null || echo 0; }
# usr(user+nice) sys idle io irq sirq
cpu_snap()    { awk '/^cpu /{print $2+$3, $4, $5, $6, $7, $8}' /proc/stat; }

# Thong tin ton CPU (lsmod, df, iptables) cache 10 giay: trang web poll moi 3 giay
SLOWF=/tmp/cake.slow
slow_info() {
  now=$(cut -d. -f1 /proc/uptime); ts=$(head -n1 $SLOWF 2>/dev/null)
  if [ -n "$ts" ] && [ "$ts" -le "$now" ] && [ $((now-ts)) -lt 10 ]; then tail -n +2 $SLOWF; return; fi
  n=$(dscp_count)
  {
    echo "$now"
    echo "hw_nat: module=$(lsmod 2>/dev/null | awk '$1=="hw_nat"{f=1} END{print f?"da nap":"khong"}')  hw_nat_mode=$(g hw_nat_mode '?')  sfe_enable=$(g sfe_enable '?')"
    echo "tmp_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2{print $2" "$3}')"
    echo "dscp_rules=$n"
    echo "dscp_hook=$(dscp_hook_ok "$n" && echo ok || echo no)"
  } > $SLOWF
  tail -n +2 $SLOWF
}

# khoi so lieu may doc duoc cho trang web (moi dong: khoa=gia tri)
stats_block() {
  echo "--- stats ---"
  echo "up=$(cut -d' ' -f1 /proc/uptime)"
  echo "epoch=$(cat $EPOCHF 2>/dev/null || echo 0)"
  echo "wan_rx_packets=$(ifstat "$1" rx_packets)"
  echo "wan_tx_packets=$(ifstat "$1" tx_packets)"
  echo "wan_rx_bytes=$(ifstat "$1" rx_bytes)"
  echo "wan_tx_bytes=$(ifstat "$1" tx_bytes)"
  echo "cpu=$(awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)"
  echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
  echo "memfree_kb=$(awk '/^MemFree:/{print $2}' /proc/meminfo)"
  slow_info | grep -v '^hw_nat:'
}

cmd_stop() {   # cmd_stop [nofb]
  kill_daemon
  clean_dscp_rules
  clear_qdisc "$(get_wan)" "$(cat $WANF 2>/dev/null)"
  rm -f $WANF $EPOCHF $SIGF
  log "CAKE đã tắt"
  [ "$1" = nofb ] || [ "$(g cake_enable 0)" = "1" ] || fallback_qdisc
}
cmd_start() {
  kill_daemon
  if [ "$(g cake_enable 0)" = "1" ]; then
    # ap dung NGAY (dong bo) de rc/webui tra ve khi CAKE da len that; daemon chi giam sat
    apply; rc=$?; trace "start: apply rc=$rc"
    sh "$0" daemon >/dev/null 2>&1 &
    echo $! > $PIDF
  elif fb_on; then
    fallback_qdisc
    sh "$0" fbdaemon >/dev/null 2>&1 &
    echo $! > $PIDF
  fi
}
cmd_diag() {
  W=$(get_wan)
  echo "== cake.sh diag =="; date; echo "uptime: $(cat /proc/uptime)"
  echo "-- nvram --"; for k in cake_enable cake_down_bw cake_up_bw cake_flow_mode cake_diffserv cake_rtt cake_overhead cake_ack_filter cake_nat cake_wash cake_dscp_auto cake_dscp_small_udp cake_custom cake_fb_qdisc hw_nat_mode sfe_enable; do echo "$k=$(nvram get $k 2>/dev/null)"; done
  echo "-- chu ky --"; echo "luu : $(cat $SIGF 2>/dev/null || echo '(không có)')"; echo "nay : $(cfg_sig "$W")"
  echo "-- lý do lệch --"; w=$(why_inactive "$W"); echo "${w:-(không lệch)}"
  echo "-- daemon --"; echo "pidfile=$(cat $PIDF 2>/dev/null) alive=$(daemon_alive && echo co || echo khong)"; echo "tien trinh: $(list_daemons | tr '\n' ' ')"
  echo "-- khóa --"; if [ -d $LOCKD ]; then echo "đang giữ bởi pid $(cat $LOCKD/pid 2>/dev/null)"; else echo "không"; fi
  echo "-- $W --"; tc -s qdisc show dev "$W" 2>&1 | head -40; tc filter show dev "$W" parent ffff: 2>&1 | head -10
  echo "-- $IFB --"; tc -s qdisc show dev $IFB 2>&1 | head -40
  echo "-- DSCP --"; echo "luat=$(dscp_count) hook=$(dscp_hook_ok && echo ok || echo no)"
  echo "-- trace (60 dong cuoi, moc = uptime giay) --"; tail -n 60 $TRACEF 2>/dev/null
}

case "$1" in
  start)   run_locked start; cmd_start ;;
  daemon) daemon ;;
  fbdaemon) fbdaemon ;;
  stop)    run_locked stop; cmd_stop ;;
  restart) run_locked restart; cmd_stop nofb; cmd_start ;;
  apply)   run_locked apply; apply ;;
  reset)
    run_locked reset
    # Bo dem cua tc (pkts/bytes/drops) chi ve 0 khi qdisc duoc tao lai -> xoa + tao lai ngay,
    # giu nguyen cau hinh. Hang doi dang cho bi bo (vai ms). Khong khoi dong lai daemon.
    [ "$(g cake_enable 0)" = "1" ] || { echo "CAKE đang tắt"; exit 1; }
    apply; rc=$?
    if [ "$rc" -eq 0 ]; then echo "Đã reset bộ đếm CAKE (tạo lại qdisc)"; else echo "Reset lỗi (mã $rc), xem: logread | grep cake"; exit 1; fi
    ;;
  status)
    W=$(get_wan)
    echo "enable=$(g cake_enable 0)  wan=$W  daemon=$(daemon_alive && echo chay || echo dung)  dscp_auto=$(g cake_dscp_auto 0)"
    slow_info | grep '^hw_nat:'
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
  dscp)
    echo "== Chẩn đoán DSCP =="
    echo "cake_dscp_auto=$(g cake_dscp_auto 0)  small_udp=$(g cake_dscp_small_udp 0)  lan=$(lan_if)"
    echo "-- module nạp --"
    lsmod 2>/dev/null | grep -iE 'dscp|length|multiport|mangle' || echo "(không thấy module dscp/length đang nạp; nếu kernel build =y thì bình thường)"
    echo "-- file module trong rootfs --"
    find /lib/modules \( -iname 'xt_dscp*' -o -iname 'xt_length*' -o -iname 'iptable_mangle*' \) 2>/dev/null | head
    modprobe xt_DSCP 2>&1; echo "modprobe xt_DSCP rc=$?"
    echo "-- thử 1 luật DSCP --"
    iptables -t mangle -X CAKE_TEST 2>/dev/null
    iptables -t mangle -N CAKE_TEST 2>&1
    iptables -t mangle -A CAKE_TEST -p tcp --dport 1 -j DSCP --set-dscp-class CS1 2>&1 && echo "OK: target DSCP chạy được"
    iptables -t mangle -F CAKE_TEST 2>/dev/null; iptables -t mangle -X CAKE_TEST 2>/dev/null
    echo "-- hiện trạng --"
    echo "hook PREROUTING:"; iptables -t mangle -S PREROUTING 2>&1 | grep -i cake || echo "  (chưa có)"
    echo "chain CAKE_DSCP:"; iptables -t mangle -S CAKE_DSCP 2>&1 | head -40
    echo "-- log cake gần nhất --"
    (logread 2>/dev/null; cat /tmp/syslog.log 2>/dev/null) | grep -i cake | tail -8
    ;;
  test)
    run_locked test
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
  diag)    cmd_diag ;;
  *) echo "Dùng: $0 {start|stop|restart|status|apply|reset|check|dscp|diag|test [dev]}"; exit 1 ;;
esac
exit 0
