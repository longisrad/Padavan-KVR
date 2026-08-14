#!/bin/sh
# ==============================================================================
# Tailscale Native Lifecycle Manager for Padavan (NEWIFI 3 D2 - MT7621)
# ==============================================================================

ts_enable=$(nvram get tailscale_enable)
ts_dns=$(nvram get tailscale_dns)
ts_route=$(nvram get tailscale_route)
ts_routes="$(nvram get tailscale_routes)"
ts_exit=$(nvram get tailscale_exit)
ts_exitip="$(nvram get tailscale_exitip)"
ts_server="$(nvram get tailscale_server)"
ts_ssh=$(nvram get tailscale_ssh)
ts_shields="$(nvram get tailscale_shields)"
ts_host="$(nvram get tailscale_host)"
ts_key=$(nvram get tailscale_key)
ts_reset="$(nvram get tailscale_reset)"
tailscaled="$(nvram get tailscale_bin)"
[ -z "$tailscaled" ] && tailscaled=/tmp/tailscaled && nvram set tailscale_bin=$tailscaled

tailscale="$(dirname "$tailscaled")/tailscale"
user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

t_CMD="$(nvram get tailscale_cmd)"
t2_CMD="$(nvram get tailscale_cmd2)"
scriptfilepath=$(cd "$(dirname "$0")"; pwd)/$(basename $0)
[ ! -d /etc/storage/tailscale ] && mkdir -p /etc/storage/tailscale
tailscale_renum=$(nvram get tailscale_renum)

BUNDLED_TS_BIN="/etc_ro/tailscaled.bin"
[ ! -f "$BUNDLED_TS_BIN" ] && BUNDLED_TS_BIN="/etc/tailscaled.bin"

HOT_RELOADED_MARKER="/tmp/.ts_hot_reloaded"

log() {
	logger -t "【Tailscale】" "$1"
}

get_free_ram_mb() {
	mem=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
	[ -z "$mem" ] && mem=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
	echo "${mem:-0}"
}

extract_bundled_ts() {
	if [ -f "$BUNDLED_TS_BIN" ]; then
		bin_path=$(dirname "$tailscaled")
		mkdir -p "$bin_path"
		log "Tìm thấy binary tích hợp trong ROM, đang giải nén vào RAM..."
		cp -f "$BUNDLED_TS_BIN" "$tailscaled"
		chmod +x "$tailscaled"
		if "$tailscaled" -version >/dev/null 2>&1; then
			log "Giải nén tailscaled thành công"
			return 0
		else
			log "File nhúng bị lỗi, chuyển sang tải từ GitHub..."
			rm -f "$tailscaled"
			return 1
		fi
	fi
	return 1
}

ts_restart() {
	relock="/var/lock/tailscale_restart.lock"
	if [ "$1" = "o" ]; then
		nvram set tailscale_renum="0"
		rm -f $relock
		return 0
	fi
	if [ "$1" = "x" ]; then
		tailscale_renum=${tailscale_renum:-"0"}
		tailscale_renum=$(expr $tailscale_renum + 1)
		nvram set tailscale_renum="$tailscale_renum"
		if [ "$tailscale_renum" -gt "3" ]; then
			I=19
			echo $I > $relock
			log "Khởi động thất bại nhiều lần, tạm dừng ${I} phút trước khi thử lại..."
			while [ $I -gt 0 ]; do
				I=$((I - 1))
				echo $I > $relock
				sleep 60
				[ "$(nvram get tailscale_renum)" = "0" ] && break
			done
			nvram set tailscale_renum="1"
		fi
		rm -f $relock
	fi
	start_ts
}

get_tag() {
	log "Đang kiểm tra phiên bản Tailscale mới nhất..."
	if ! command -v curl >/dev/null 2>&1; then
		tag="$(wget --no-check-certificate -T 10 -t 3 --user-agent "$user_agent" -qO- https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4)"
	else
		tag="$(curl -Lk --connect-timeout 5 --user-agent "$user_agent" -s https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4)"
	fi

	[ -n "$tag" ] && [ "${tag#v}" = "$tag" ] && tag="v${tag}"
	[ -z "$tag" ] && tag="v1.78.1"
	nvram set tailscale_ver_n=$tag

	if [ -f "$tailscaled" ]; then
		chmod +x $tailscaled
		ts_ver=$($tailscaled -version 2>/dev/null | sed -n 1p | awk -F '-' '{print $1}')
		[ -n "$ts_ver" ] && [ "${ts_ver#v}" = "$ts_ver" ] && ts_ver="v${ts_ver}"
		nvram set tailscale_ver="${ts_ver:-}"
	fi
}

dowload_ts() {
	tag="$1"
	[ "${tag#v}" = "$tag" ] && tag="v${tag}"
	bin_path=$(dirname "$tailscaled")
	mkdir -p "$bin_path"
	
	dl_url="https://github.com/lmq8267/tailscale/releases/download/${tag}/tailscaled_full"
	mirror_url="https://ghp.ci/https://github.com/lmq8267/tailscale/releases/download/${tag}/tailscaled_full"

	log "Bắt đầu tải ${dl_url} (RAM trống: $(get_free_ram_mb)M)..."
	curl -Lko "$tailscaled" --connect-timeout 15 --retry 2 --max-time 300 "$dl_url" || wget --no-check-certificate -T 20 -t 2 -O "$tailscaled" "$dl_url"
	
	if [ $? -ne 0 ] || [ ! -s "$tailscaled" ]; then
		log "Tải trực tiếp thất bại, thử qua máy chủ Mirror..."
		curl -Lko "$tailscaled" --connect-timeout 15 --retry 2 --max-time 300 "$mirror_url" || wget --no-check-certificate -T 20 -t 2 -O "$tailscaled" "$mirror_url"
	fi

	if [ -s "$tailscaled" ]; then
		chmod +x $tailscaled
		if "$tailscaled" -version >/dev/null 2>&1; then
			log "Tải tailscaled thành công!"
			ts_ver=$($tailscaled -version | sed -n 1p | awk -F '-' '{print $1}')
			[ -n "$ts_ver" ] && [ "${ts_ver#v}" = "$ts_ver" ] && ts_ver="v${ts_ver}"
			nvram set tailscale_ver="${ts_ver:-}"
		else
			log "File tải về bị lỗi!"
			rm -f "$tailscaled"
		fi
	else
		log "Tải thất bại!"
		rm -f "$tailscaled"
	fi
}

update_ts() {
	get_tag
	[ -z "$tag" ] && exit 1
	clean_tag="${tag#v}"
	clean_ver="${ts_ver#v}"
	if [ -n "$clean_tag" ] && [ -n "$clean_ver" ] && [ "$clean_tag" != "$clean_ver" ]; then
		log "Cập nhật từ ${ts_ver} lên ${tag}..."
		dowload_ts "$tag"
	else
		log "Đã ở bản mới nhất (${tag})"
	fi
	exit 0
}

get_info() {
	nvram set tailscale_info=""
	$tailscale status >/tmp/tailscale.status 2>&1
	if [ -z "$(grep -i 'Logged out' /tmp/tailscale.status)" ]; then
		cat /tmp/tailscale.status >>/tmp/tailscale.log 
		ts_IP="$($tailscale ip 2>/dev/null | sed -n 1p)"
		if echo "$ts_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
			ts_info="$($tailscale whois $ts_IP 2>/dev/null)"
			device_name=$(echo "$ts_info" | awk -F 'Name: ' 'NR==2 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			device_id=$(echo "$ts_info" | awk -F 'ID: ' 'NR==3 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			user_name=$(echo "$ts_info" | awk -F 'Name: ' 'NR==6 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			user_id=$(echo "$ts_info" | awk -F 'ID: ' 'NR==7 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			
			[ -n "$user_name" ] && adminuser="Account: $user_name "
			[ -n "$ts_IP" ] && adminip=" IP: $ts_IP "
			[ -n "$device_id" ] && adminid=" ID: $device_id "
			log "Tên thiết bị: $device_name | IP Tailscale: $ts_IP | ID: $device_id"
			nvram set tailscale_info="${adminuser}${adminip}${adminid}"
		fi
	fi
	rm -f /tmp/tailscale.status
}

get_login() {
	nvram set tailscale_login=""
	retry=0
	login_url=""
	while [ $retry -lt 12 ]; do
		$tailscale status >/tmp/tailscale.status 2>&1
		if [ -n "$(grep -i 'Logged out' /tmp/tailscale.status)" ]; then
			login_url=$(cat /tmp/tailscale.status | awk -F 'Log in at: ' '{print $2}')
			[ -n "$login_url" ] && break
		else
			get_info
			rm -f /tmp/tailscale.status
			return
		fi
		sleep 1
		retry=$((retry + 1))
	done
	log "Đường dẫn đăng nhập thiết bị: $login_url"
	nvram set tailscale_login="$login_url"
	rm -f /tmp/tailscale.status
}

ts_keep() {
	if [ -s /tmp/script/_opt_script_check ]; then
		sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check
		cat >> "/tmp/script/_opt_script_check" <<-OSC
		[ -z "\`pidof tailscaled\`" ] && logger -t "Process Watchdog" "tailscaled process dropped" && eval "$scriptfilepath start &" && sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check #【Tailscaled】
		[ -z "\$(iptables -L -n -v | grep 'tailscale0')" ] && logger -t "Process Watchdog" "tailscaled firewall rule invalid" && eval "$scriptfilepath start &" && sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check #【Tailscaled】
		[ -s /tmp/tailscale.log ] && [ "\$(stat -c %s /tmp/tailscale.log)" -gt 307200 ] && echo "" > /tmp/tailscale.log & #【Tailscaled】
		OSC
	fi
	get_login
}

build_up_cmd() {
	CMD=""
	if [ "$ts_enable" = "1" ]; then
		CMD="up"
		[ "$ts_dns" = "1" ] || CMD="${CMD} --accept-dns=false"
		[ "$ts_route" = "1" ] && CMD="${CMD} --accept-routes"
		[ -n "$ts_routes" ] && CMD="${CMD} --advertise-routes=$(echo $ts_routes | tr -d ' ')"
		[ "$ts_exit" = "1" ] && CMD="${CMD} --advertise-exit-node"
		[ -n "$ts_exitip" ] && CMD="${CMD} --exit-node=$(echo $ts_exitip | tr -d ' ') --exit-node-allow-lan-access"
		[ -n "$ts_server" ] && CMD="${CMD} --login-server=$(echo $ts_server | tr -d ' ')"
		[ "$ts_ssh" = "1" ] && CMD="${CMD} --ssh"
		[ "$ts_shields" = "1" ] && CMD="${CMD} --shields-up"
		[ -n "$ts_host" ] && CMD="${CMD} --hostname=$(echo $ts_host | tr -d ' ')"
		[ -n "$ts_key" ] && CMD="${CMD} --auth-key=$(echo $ts_key | tr -d ' ')"
		[ -n "$t2_CMD" ] && CMD="${CMD} ${t2_CMD}"
		[ "$ts_reset" = "1" ] && CMD="${CMD} --reset"
		CMD="${tailscale} ${CMD}"
	elif [ "$ts_enable" = "2" ]; then
		if [ -n "$t_CMD" ]; then
			CMD="${tailscale} ${t_CMD}"
		else
			CMD="${tailscale} up"
			nvram set tailscale_cmd="up"
		fi
	fi
}

apply_ts_settings() {
	log "Đổi cấu hình runtime qua 'tailscale up'..."
	build_up_cmd
	if [ -z "$CMD" ]; then
		stop_ts
		start_ts &
		return
	fi
	eval "$CMD >>/tmp/tailscale.log 2>&1" &
	sleep 3
	get_info
	touch "$HOT_RELOADED_MARKER"
}

start_ts() {
	if [ -f "$HOT_RELOADED_MARKER" ] && [ -n "$(pidof tailscaled)" ]; then
		rm -f "$HOT_RELOADED_MARKER"
		exit 0
	fi
	rm -f "$HOT_RELOADED_MARKER"

	[ "$ts_enable" = "0" ] && exit 1

	# Kiểm tra xung đột với Sing-box Tailscale Endpoint
	if [ "$(nvram get singbox_enable)" = "1" ] && [ "$(nvram get singbox_ts_enable)" = "1" ]; then
		log "CẢNH BÁO: Sing-box Tailscale Endpoint đang bật -> CHẶN Tailscale native để tránh xung đột!"
		exit 1
	fi

	if [ "$ts_enable" = "3" ]; then
		log "Đang xoá sạch dữ liệu /etc/storage/tailscale/* ..."
		kill_ts
		rm -rf /etc/storage/tailscale/*
		nvram set tailscale_enable=0
		nvram set tailscale_login=""
		nvram set tailscale_info=""
		exit 0
	fi 

	log "Đang khởi động Tailscale..."
	sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check

	[ ! -f "$tailscaled" ] && extract_bundled_ts
	get_tag
	if [ -f "$tailscaled" ]; then
		chmod +x "$tailscaled"
		if ! "$tailscaled" -version >/dev/null 2>&1; then
			rm -rf "$tailscaled"
		fi
	fi
	if [ ! -f "$tailscaled" ]; then
		[ -z "$tag" ] && tag="v1.78.1"
		dowload_ts "$tag"
	fi

	if [ ! -s "$tailscaled" ]; then
		log "LỖI: Không có binary /tmp/tailscaled hợp lệ!"
		ts_restart x
		exit 1
	fi

	kill_ts
	chmod +x "$tailscaled"
	path=$(dirname "$tailscaled")
	mkdir -p "/var/run/tailscale" "/etc/storage/tailscale/lib"

	ln -sf "$tailscaled" "${path}/tailscale"

	tdCMD="$tailscaled --state=/etc/storage/tailscale/lib/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --port=41641"
	
	export GOMEMLIMIT=96MiB
	export GOGC=50
	
	eval "$tdCMD >>/tmp/tailscale.log 2>&1" &
	sleep 3
	
	pid_td=$(pidof tailscaled)
	if [ -n "$pid_td" ]; then
		log "Tiến trình tailscaled đã chạy (PID: $pid_td)"
		ts_restart o
		iptables -C INPUT -i tailscale0 -j ACCEPT 2>/dev/null || iptables -I INPUT -i tailscale0 -j ACCEPT
	else
		log "Khởi động tailscaled thất bại, thử lại sau 10s..."
		sleep 10
		ts_restart x
	fi

	CMD=""
	build_up_cmd
	eval "$CMD >>/tmp/tailscale.log 2>&1" &
	sleep 3
	
	ts_keep
	exit 0
}

kill_ts() {
	rm -f /tmp/tailscale.log
	if [ -n "$(pidof tailscaled)" ]; then
		log "Đang dừng tiến trình tailscaled..."
		$tailscale down 2>/dev/null
		killall tailscaled 2>/dev/null
		killall tailscale 2>/dev/null

		tries=0
		while [ -n "$(pidof tailscaled)" ] && [ $tries -lt 4 ]; do
			sleep 1
			tries=$((tries + 1))
		done

		if [ -n "$(pidof tailscaled)" ]; then
			killall -9 tailscaled 2>/dev/null
			killall -9 tailscale 2>/dev/null
			sleep 1
		fi
	fi

	# QUÉT SẠCH TÀN DƯ ROUTING TABLE 52 ĐỂ KHÔNG BAO GIỜ BỊ NGHẼN MẠNG
	while ip rule del table 52 2>/dev/null; do :; done
	ip route flush table 52 2>/dev/null

	# Dọn dẹp MagicDNS nếu bị dính trong resolv.conf
	if [ -f /etc/resolv.conf ]; then
		sed -i '/^nameserver 100\./d' /etc/resolv.conf
	fi
}

stop_ts() {
	if [ -n "$(pidof tailscaled)" ] && { [ "$ts_enable" = "1" ] || [ "$ts_enable" = "2" ]; }; then
		apply_ts_settings
		return 0
	fi

	log "Đang tắt hoàn toàn Tailscale..."
	sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check
	kill_ts
	iptables -D INPUT -i tailscale0 -j ACCEPT 2>/dev/null
	log "Tailscale đã dừng sạch sẽ!"
}

case $1 in
start)   start_ts & ;;
stop)    stop_ts ;;
restart) stop_ts; start_ts & ;;
update)  update_ts & ;;
*)       echo "check" ;;
esac
