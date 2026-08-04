#!/bin/sh

CONF_FILE="/etc/storage/wg0.conf"
TABLE_ID=51820
FWMARK=51820

tun_name="$(nvram get wireguard_tun)"
wg_mtu="$(nvram get wireguard_mtu)"
wg_enable="$(nvram get wireguard_enable)"
[ -z "$tun_name" ] && tun_name="wg0"
[ -z "$wg_mtu" ] && wg_mtu="1420"
tun_name="$(echo $tun_name | tr -d ' ')"
localip="$(nvram get wireguard_localip)"
localip6="$(nvram get wireguard_localip6)"

log() {
	logger -t "【WIREGUARD】" "$1"
}

# Extract every AllowedIPs entry from the peer section(s) of the config file
get_allowed_ips() {
	grep -i "^[[:space:]]*AllowedIPs" "$CONF_FILE" \
		| sed 's/^[^=]*=//' \
		| tr ',' '\n' \
		| sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
		| grep -v '^$'
}

setup_routing() {
	allowed_ips="$(get_allowed_ips)"
	has_default_v4=0
	has_default_v6=0
	for ip in $allowed_ips; do
		[ "$ip" = "0.0.0.0/0" ] && has_default_v4=1
		[ "$ip" = "::/0" ] && has_default_v6=1
	done

	if [ "$has_default_v4" = "1" ] || [ "$has_default_v6" = "1" ]; then
		# Full-tunnel: route everything through wg0 without looping the
		# tunnel's own encrypted packets back into itself (same trick wg-quick uses)
		wg set ${tun_name} fwmark ${FWMARK}
		if [ "$has_default_v4" = "1" ]; then
			ip -4 route add 0.0.0.0/0 dev ${tun_name} table ${TABLE_ID} 2>/dev/null
			ip -4 rule add not fwmark ${FWMARK} table ${TABLE_ID} priority 51820 2>/dev/null
			ip -4 rule add table main suppress_prefixlength 0 priority 51821 2>/dev/null
		fi
		if [ "$has_default_v6" = "1" ]; then
			ip -6 route add ::/0 dev ${tun_name} table ${TABLE_ID} 2>/dev/null
			ip -6 rule add not fwmark ${FWMARK} table ${TABLE_ID} priority 51820 2>/dev/null
			ip -6 rule add table main suppress_prefixlength 0 priority 51821 2>/dev/null
		fi
		log "Full-tunnel routing enabled (all traffic -> ${tun_name})"
	fi

	# Any other, more specific AllowedIPs entries are plain split-tunnel routes
	for ip in $allowed_ips; do
		case "$ip" in
			0.0.0.0/0|::/0) continue ;;
			*:*) ip -6 route add ${ip} dev ${tun_name} 2>/dev/null ;;
			*)   ip -4 route add ${ip} dev ${tun_name} 2>/dev/null ;;
		esac
	done
}

teardown_routing() {
	ip -4 rule del not fwmark ${FWMARK} table ${TABLE_ID} priority 51820 2>/dev/null
	ip -4 rule del table main suppress_prefixlength 0 priority 51821 2>/dev/null
	ip -6 rule del not fwmark ${FWMARK} table ${TABLE_ID} priority 51820 2>/dev/null
	ip -6 rule del table main suppress_prefixlength 0 priority 51821 2>/dev/null
	ip -4 route flush table ${TABLE_ID} 2>/dev/null
	ip -6 route flush table ${TABLE_ID} 2>/dev/null
}

start_wg() {
	[ "$wg_enable" = "1" ] || exit 1
	if [ ! -s "$CONF_FILE" ]; then
		log "$CONF_FILE is empty, exiting."
		exit 1
	fi

	log "Starting WireGuard..."
	ifconfig ${tun_name} down 2>/dev/null
	ip link del dev ${tun_name} 2>/dev/null

	log "Creating interface ${tun_name}"
	ip link add dev ${tun_name} type wireguard
	log "Applying config from $CONF_FILE"
	wg setconf ${tun_name} "$CONF_FILE"
	[ -z "$localip" ] || ip -4 addr add dev ${tun_name} ${localip}
	[ -z "$localip6" ] || ip -6 addr add dev ${tun_name} ${localip6}
	ip link set dev ${tun_name} mtu ${wg_mtu}

	iptables -I INPUT -i ${tun_name} -j ACCEPT
	iptables -I FORWARD -i ${tun_name} -j ACCEPT
	iptables -I FORWARD -o ${tun_name} -j ACCEPT
	iptables -t nat -I POSTROUTING -o ${tun_name} -j MASQUERADE

	ifconfig ${tun_name} up
	if [ $? -eq 0 ]; then
		setup_routing
		log "Started"
	else
		log "Failed to bring up ${tun_name}"
	fi
}

stop_wg() {
	teardown_routing
	ifconfig ${tun_name} down 2>/dev/null
	ip link del dev ${tun_name} 2>/dev/null
	iptables -D INPUT -i ${tun_name} -j ACCEPT 2>/dev/null
	iptables -D FORWARD -i ${tun_name} -j ACCEPT 2>/dev/null
	iptables -D FORWARD -o ${tun_name} -j ACCEPT 2>/dev/null
	iptables -t nat -D POSTROUTING -o ${tun_name} -j MASQUERADE 2>/dev/null
	log "WireGuard stopped"
}

case $1 in
start)
	start_wg
	;;
stop)
	stop_wg
	;;
*)
	echo "check"
	;;
esac
