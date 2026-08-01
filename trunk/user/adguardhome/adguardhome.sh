#!/bin/sh

scriptfilepath=$(cd "$(dirname "$0")"; pwd)/$(basename $0)
change_dns() {
if [ "$(nvram get adg_redirect)" = 1 ]; then
sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
sed -i '/server=127.0.0.1/d' /etc/storage/dnsmasq/dnsmasq.conf
cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
/sbin/restart_dhcpd
logger -t "【AdGuardHome】" "Added DNS forwarding to port 5335"
fi
}

del_dns() {
sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
/sbin/restart_dhcpd
}

set_iptable() {
    if [ "$(nvram get adg_redirect)" = 2 ]; then
  IPS="`ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F : '{print $2}'`"
  for IP in $IPS
  do
    iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
  done

  IPS="`ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}'`"
  for IP in $IPS
  do
    ip6tables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    ip6tables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
  done
    logger -t "【AdGuardHome】" "Redirected port 53"
    fi
}

clear_iptable() {
  OLD_PORT="5335"
  IPS="`ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F : '{print $2}'`"
  for IP in $IPS
  do
    iptables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports $OLD_PORT >/dev/null 2>&1
    iptables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports $OLD_PORT >/dev/null 2>&1
  done

  IPS="`ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}'`"
  for IP in $IPS
  do
    ip6tables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports $OLD_PORT >/dev/null 2>&1
    ip6tables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports $OLD_PORT >/dev/null 2>&1
  done

}

getconfig() {
adg_file="/etc/storage/adg.sh"
if [ ! -f "$adg_file" ] || [ ! -s "$adg_file" ] ; then
  cat > "$adg_file" <<-\EEE
http:
  address: 0.0.0.0:3030
auth_name: admin
auth_pass: admin
language: zh-cn
dns:
  bind_host: 0.0.0.0
  port: 5335
  ratelimit: 0
  upstream_dns:
  - tcp://1.0.0.1
  bootstrap_dns: tcp://1.0.0.1
  all_servers: true
tls:
  enabled: false

EEE
  chmod 755 "$adg_file"
fi
}
adg_renum=`nvram get adg_renum`

adg_restart () {
relock="/var/lock/AdGuardHome_restart.lock"
if [ "$1" = "o" ] ; then
	nvram set adg_renum="0"
	[ -f $relock ] && rm -f $relock
	return 0
fi
if [ "$1" = "x" ] ; then
	adg_renum=${adg_renum:-"0"}
	adg_renum=`expr $adg_renum + 1`
	nvram set adg_renum="$adg_renum"
	if [ "$adg_renum" -gt "3" ] ; then
		I=19
		echo $I > $relock
		logger -t "【AdGuardHome】" "Multiple start attempts failed, waiting 【"`cat $relock`" min】 before auto-retry"
		while [ $I -gt 0 ]; do
			I=$(($I - 1))
			echo $I > $relock
			sleep 60
			[ "$(nvram get adg_renum)" = "0" ] && break
   			#[ "$(nvram get adg_enable)" = "0" ] && exit 0
			[ $I -lt 0 ] && break
		done
		nvram set adg_renum="1"
	fi
	[ -f $relock ] && rm -f $relock
fi
start_adg
}

find_bin() {
SVC_PATH="$(nvram get adg_bin)"

dirs="/etc/storage/bin
/tmp/AdGuardHome
/usr/bin"

if [ -z "$SVC_PATH" ] ; then
  for dir in $dirs ; do
    if [ -f "$dir/AdGuardHome" ] ; then
        SVC_PATH="$dir/AdGuardHome"
        [ ! -x "$SVC_PATH" ] && chmod +x $SVC_PATH
        break
    fi
  done
  [ -z "$SVC_PATH" ] && SVC_PATH="/tmp/AdGuardHome/AdGuardHome"
fi
}

get_tag() {
	user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

	curltest=`which curl`
	logger -t "【AdGuardHome】" "Fetching latest version..."
    	if [ -z "$curltest" ] || [ ! -s "`which curl`" ] ; then
      		tag="$( wget --no-check-certificate -T 5 -t 3 --user-agent "$user_agent" --output-document=-  https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
	 	[ -z "$tag" ] && tag="$( wget --no-check-certificate -T 5 -t 3 --user-agent "$user_agent" --quiet --output-document=-  https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
    	else
      		tag="$( curl -k --connect-timeout 3 --user-agent "$user_agent"  https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
       	[ -z "$tag" ] && tag="$( curl -Lk --connect-timeout 3 --user-agent "$user_agent" -s  https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest  2>&1 | grep 'tag_name' | cut -d\" -f4 )"
        fi
	[ -z "$tag" ] && logger -t "【AdGuardHome】" "Could not fetch latest version" && tag="v0.107.54"

}
github_proxys="DIRECT $(nvram get github_proxy)"

dl_adg() {
	find_bin
	if [ ! -f "$SVC_PATH" ] ; then
		logger -t "【AdGuardHome】" "$SVC_PATH not found, downloading AdGuardHome"
		get_tag
  		adg_path=$(dirname "$SVC_PATH")
    		[ ! -d "$adg_path" ] && mkdir -p "$adg_path"
		logger -t "【AdGuardHome】" "Downloading version ${tag}, this may be slow, please wait"
		for proxy in $github_proxys ; do
  			[ "$proxy" = "DIRECT" ] && proxy=""
  			length=$(wget --no-check-certificate -T 10 -t 3 "${proxy}https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz" -O /dev/null --spider --server-response 2>&1 | grep "[Cc]ontent-[Ll]ength" | grep -Eo '[0-9]+' | tail -n 1)
 			length=`expr $length + 512000`
			length=`expr $length / 1048576`
 			adg_size0="$(check_disk_size $adg_path)"
 			[ ! -z "$length" ] && logger -t "【AdGuardHome】" "Program size ${length}M, free space at program path ${adg_size0}M "
			curl -Lkso "/tmp/AdGuardHome/AdGuardHome.tar.gz" --connect-timeout 10 --retry 2 --max-time 90 "${proxy}https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz" || wget --no-check-certificate -T 15 -t 2 -q -O "/tmp/AdGuardHome/AdGuardHome.tar.gz" "${proxy}https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz"
			if [ "$?" = 0 ] ; then
				tar -xzvf /tmp/AdGuardHome/AdGuardHome.tar.gz -C $adg_path
    				rm -f /tmp/AdGuardHome/AdGuardHome.tar.gz
		 		cd ${adg_path} ; rm -f ./LICENSE.txt ./README.md ./CHANGELOG.md ./AdGuardHome.sig
		 		chmod +x $SVC_PATH
				if [[ "$($SVC_PATH -h 2>&1 | wc -l)" -gt 3 ]] ; then
					logger -t "【AdGuardHome】" "$SVC_PATH downloaded successfully"
					break
       				else
	   				logger -t "【AdGuardHome】" "Download incomplete"
					rm -f $SVC_PATH
	  			fi
	  		else
	  			logger -t "【AdGuardHome】" "Download failed, please manually download ${proxy}https://github.com/AdguardTeam/AdGuardHome/releases/download/${tag}/AdGuardHome_linux_mipsle_softfloat.tar.gz then extract and upload to $SVC_PATH"
		 	fi
		done
	fi     
}

adg_keep() {
	logger -t "【AdGuardHome】" "Watchdog started"
	if [ -s /tmp/script/_opt_script_check ]; then
	sed -Ei '/【AdGuardHome】|^$/d' /tmp/script/_opt_script_check
	cat >> "/tmp/script/_opt_script_check" <<-OSC
	[ -z "\`pidof AdGuardHome\`" ] && logger -t "Process Watchdog" "AdGuardHome process dropped" && eval "$scriptfilepath start &" && sed -Ei '/【AdGuardHome】|^$/d' /tmp/script/_opt_script_check #【AdGuardHome】
	OSC

	fi

}

start_adg() {
  mkdir -p /tmp/AdGuardHome
  mkdir -p /etc/storage/AdGuardHome
  logger -t "【AdGuardHome】" "Starting..."
  sed -Ei '/【AdGuardHome】|^$/d' /tmp/script/_opt_script_check
  find_bin
  [ ! -x "$SVC_PATH" ] && chmod +x $SVC_PATH
  [[ "$($SVC_PATH -h 2>&1 | wc -l)" -lt 3 ]] && rm $SVC_PATH
  if [ ! -f "$SVC_PATH" ] || [[ "$($SVC_PATH -h 2>&1 | wc -l)" -lt 3 ]] ; then
  dl_adg
  fi
  adgenable=$(nvram get adg_enable)
  if [ "$adgenable" = "1" ] ;then
  getconfig
  change_dns
  set_iptable
  logger -t "【AdGuardHome】" "Running $SVC_PATH"
  [ ! -x "$SVC_PATH" ] && chmod +x $SVC_PATH
  eval "$SVC_PATH -c $adg_file -w /tmp/AdGuardHome -v" &
  sleep 4
  	if [ ! -z "`pidof AdGuardHome`" ] ; then
 		mem=$(cat /proc/$(pidof AdGuardHome)/status | grep -w VmRSS | awk '{printf "%.1f MB", $2/1024}')
   		cpui="$(top -b -n1 | grep -E "$(pidof AdGuardHome)" 2>/dev/null| grep -v grep | awk '{for (i=1;i<=NF;i++) {if ($i ~ /AdGuardHome/) break; else cpu=i}} END {print $cpu}')"
		logger -t "【AdGuardHome】" "Running successfully!"
  		logger -t "【AdGuardHome】" "Memory usage ${mem}  CPU usage ${cpui}%"
  		adg_restart o
		echo `date +%s` > /tmp/vntcli_time
		vnt_rules
	else
		logger -t "【AdGuardHome】" "Failed to run, check if ${VNTCLI} downloaded completely, auto-retry in 10 seconds"
  		sleep 10
  		adg_restart x
	fi
 adg_keep
  fi
  
}

stop_adg() {
scriptname=$(basename $0)
sed -Ei '/【AdGuardHome】|^$/d' /tmp/script/_opt_script_check
rm -rf /tmp/AdGuardHome
killall -9 AdGuardHome
killall AdGuardHome
del_dns
clear_iptable
logger -t "【AdGuardHome】" "Stopping AdGuardHome"
if [ ! -z "$scriptname" ] ; then
	eval $(ps -w | grep "$scriptname" | grep -v $$ | grep -v grep | awk '{print "kill "$1";";}')
	eval $(ps -w | grep "$scriptname" | grep -v $$ | grep -v grep | awk '{print "kill -9 "$1";";}')
fi
}

case $1 in
start)
  start_adg &
  ;;
stop)
  stop_adg
  ;;
*)
  echo "check"
  ;;
esac
