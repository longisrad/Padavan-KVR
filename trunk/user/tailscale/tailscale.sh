#!/bin/sh

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
tailscale_renum=`nvram get tailscale_renum`

BUNDLED_TS_BIN="/etc/tailscaled.bin"

get_free_ram_mb() {
	mem=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
	[ -z "$mem" ] && mem=$(awk '/MemFree/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
	echo "${mem:-0}"
}

extract_bundled_ts() {
	if [ -f "$BUNDLED_TS_BIN" ] ; then
		bin_path=$(dirname "$tailscaled")
		[ ! -d "$bin_path" ] && mkdir -p "$bin_path"
		logger -t "【Tailscale】" "Found bundled tailscaled in firmware, copying to RAM..."
		cp "$BUNDLED_TS_BIN" "$tailscaled"
		chmod +x "$tailscaled"
		if "$tailscaled" -version >/dev/null 2>&1 ; then
			logger -t "【Tailscale】" "Bundled tailscaled extracted successfully"
			return 0
		else
			logger -t "【Tailscale】" "Bundled file corrupt, falling back to network download"
			rm -f "$tailscaled"
			return 1
		fi
	fi
	return 1
}

ts_restart () {
relock="/var/lock/tailscale_restart.lock"
if [ "$1" = "o" ] ; then
	nvram set tailscale_renum="0"
	[ -f $relock ] && rm -f $relock
	return 0
fi
if [ "$1" = "x" ] ; then
	tailscale_renum=${tailscale_renum:-"0"}
	tailscale_renum=`expr $tailscale_renum + 1`
	nvram set tailscale_renum="$tailscale_renum"
	if [ "$tailscale_renum" -gt "3" ] ; then
		I=19
		echo $I > $relock
		logger -t "【Tailscale】" "Multiple start attempts failed, waiting 【"`cat $relock`" min】 before auto-retry"
		while [ $I -gt 0 ]; do
			I=$(($I - 1))
			echo $I > $relock
			sleep 60
			[ "$(nvram get tailscale_renum)" = "0" ] && break
			[ $I -lt 0 ] && break
		done
		nvram set tailscale_renum="1"
	fi
	[ -f $relock ] && rm -f $relock
fi
start_ts
}

get_tag() {
	curltest=`which curl`
	logger -t "【Tailscale】" "Fetching latest version..."
	if [ -z "$curltest" ] || [ ! -s "`which curl`" ] ; then
		tag="$( wget --no-check-certificate -T 10 -t 3 --user-agent "$user_agent" --output-document=- https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
		[ -z "$tag" ] && tag="$( wget --no-check-certificate -T 10 -t 3 --user-agent "$user_agent" --quiet --output-document=- https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
	else
		tag="$( curl -k --connect-timeout 5 --user-agent "$user_agent" https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
		[ -z "$tag" ] && tag="$( curl -Lk --connect-timeout 5 --user-agent "$user_agent" -s https://api.github.com/repos/lmq8267/tailscale/releases/latest 2>&1 | grep 'tag_name' | cut -d\" -f4 )"
	fi

	[ -n "$tag" ] && [ "${tag#v}" = "$tag" ] && tag="v${tag}"
	[ -z "$tag" ] && logger -t "【Tailscale】" "Could not fetch latest version" && tag="v1.78.1"
	
	nvram set tailscale_ver_n=$tag

	if [ -f "$tailscaled" ] ; then
		chmod +x $tailscaled
		ts_ver=$($tailscaled -version | sed -n 1p | awk -F '-' '{print $1}')
		[ -n "$ts_ver" ] && [ "${ts_ver#v}" = "$ts_ver" ] && ts_ver="v${ts_ver}"
		nvram set tailscale_ver="${ts_ver:-}"
	fi
}

dowload_ts() {
	tag="$1"
	[ "${tag#v}" = "$tag" ] && tag="v${tag}"

	bin_path=$(dirname "$tailscaled")
	[ ! -d "$bin_path" ] && mkdir -p "$bin_path"
	
	dl_url="https://github.com/lmq8267/tailscale/releases/download/${tag}/tailscaled_full"
	mirror_url="https://ghp.ci/https://github.com/lmq8267/tailscale/releases/download/${tag}/tailscaled_full"

	logger -t "【Tailscale】" "Starting download ${dl_url} to $tailscaled"
	tailscaled_size0="$(get_free_ram_mb)"
	logger -t "【Tailscale】" "Free RAM space: ${tailscaled_size0}M"
	
	curl -Lko "$tailscaled" --connect-timeout 15 --retry 2 --max-time 300 "$dl_url" || wget --no-check-certificate -T 20 -t 2 -O "$tailscaled" "$dl_url"
	
	if [ "$?" != 0 ] || [ ! -s "$tailscaled" ]; then
		logger -t "【Tailscale】" "Direct download failed, trying mirror source..."
		curl -Lko "$tailscaled" --connect-timeout 15 --retry 2 --max-time 300 "$mirror_url" || wget --no-check-certificate -T 20 -t 2 -O "$tailscaled" "$mirror_url"
	fi

	if [ -f "$tailscaled" ] && [ -s "$tailscaled" ] ; then
		chmod +x $tailscaled
		if "$tailscaled" -version >/dev/null 2>&1 ; then
			logger -t "【Tailscale】" "$tailscaled downloaded successfully"
			ts_ver=$($tailscaled -version | sed -n 1p | awk -F '-' '{print $1}')
			[ -n "$ts_ver" ] && [ "${ts_ver#v}" = "$ts_ver" ] && ts_ver="v${ts_ver}"
			nvram set tailscale_ver="${ts_ver:-}"
		else
			logger -t "【Tailscale】" "Download incomplete or corrupt"
			rm -f $tailscaled
		fi
	else
		logger -t "【Tailscale】" "Download failed"
		rm -f $tailscaled
	fi
}

update_ts() {
	get_tag
	[ -z "$tag" ] && logger -t "【Tailscale】" "Could not fetch latest version" && exit 1
	clean_tag="${tag#v}"
	clean_ver="${ts_ver#v}"
	if [ -n "$clean_tag" ] && [ -n "$clean_ver" ] ; then
		if [ "$clean_tag" != "$clean_ver" ] ; then
			logger -t "【Tailscale】" "Current version ${ts_ver}, latest version ${tag}"
			dowload_ts $tag
		else
			logger -t "【Tailscale】" "Already on the latest version ${tag}, no update needed!"
		fi
	fi
	exit 0
}

get_info() {
	nvram set tailscale_info=""
	$tailscale status >/tmp/tailscale.status 2>&1
	if [ -z "$(grep 'Logged' /tmp/tailscale.status | grep 'out')" ] ; then
		cat /tmp/tailscale.status >>/tmp/tailscale.log 
		ts_IP="$($tailscale ip | sed -n 1p)"
		if echo "$ts_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
			ts_info="$($tailscale whois $ts_IP)"
			device_name=$(echo "$ts_info" | awk -F 'Name: ' 'NR==2 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			device_id=$(echo "$ts_info" | awk -F 'ID: ' 'NR==3 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			user_name=$(echo "$ts_info" | awk -F 'Name: ' 'NR==6 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			user_id=$(echo "$ts_info" | awk -F 'ID: ' 'NR==7 {print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			
			[ -n "$user_name" ] && adminuser="Bound account: $user_name "
			[ -n "$ts_IP" ] && adminip=" Device IP: $ts_IP "
			[ -n "$device_id" ] && adminid=" Device ID: $device_id "
			logger -t "【Tailscale】" "Device Name: $device_name  Device IP: $ts_IP  Device ID: $device_id"
			logger -t "【Tailscale】" "Bound Account: $user_name  Account ID: $user_id"
			nvram set tailscale_info="${adminuser}${adminip}${adminid}"
		fi
	fi
	rm -f /tmp/tailscale.status
}

get_login() {
	nvram set tailscale_login=""
	retry=0
	login_url=""
	while [ $retry -lt 15 ]; do
		$tailscale status >/tmp/tailscale.status 2>&1
		if [ -n "$(grep 'Logged' /tmp/tailscale.status | grep 'out')" ] ; then
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
	logger -t "【Tailscale】" "First install or key file empty, fetching device login URL..."
	logger -t "【Tailscale】" "Device login URL: $login_url"
	nvram set tailscale_login="$login_url"
	logger -t "【Tailscale】" "After binding, do not reboot immediately to avoid losing key state"
	[ -z "$login_url" ] && logger -t "【Tailscale】" "Could not get device login URL after ${retry}s, run '$tailscale login' manually via SSH"
	rm -f /tmp/tailscale.status
}

ts_keep() {
	logger -t "【Tailscale】" "Watchdog started"
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
	if [ "$ts_enable" = "1" ] ; then
		CMD="up"
		[ "$ts_dns" = "1" ] || CMD="${CMD} --accept-dns=false"
		[ "$ts_route" = "1" ] && CMD="${CMD} --accept-routes"
		[ -z "$ts_routes" ] || ts_routes="$(echo $ts_routes | tr -d ' ')"
		[ -z "$ts_routes" ] || CMD="${CMD} --advertise-routes=${ts_routes}"
		[ "$ts_exit" = "1" ] && CMD="${CMD} --advertise-exit-node"
		[ -z "$ts_exitip" ] || ts_exitip="$(echo $ts_exitip | tr -d ' ')"
		[ -z "$ts_exitip" ] || CMD="${CMD} --exit-node=${ts_exitip} --exit-node-allow-lan-access"
		[ -z "$ts_server" ] || ts_server="$(echo $ts_server | tr -d ' ')"
		[ -z "$ts_server" ] || CMD="${CMD} --login-server=${ts_server}"
		[ "$ts_ssh" = "1" ] && CMD="${CMD} --ssh"
		[ "$ts_shields" = "1" ] && CMD="${CMD} --shields-up"
		[ -z "$ts_host" ] || ts_host="$(echo $ts_host | tr -d ' ')"
		[ -z "$ts_host" ] || CMD="${CMD} --hostname=${ts_host}"
		[ -z "$ts_key" ] || ts_key="$(echo $ts_key | tr -d ' ')"
		[ -z "$ts_key" ] || CMD="${CMD} --auth-key=${ts_key}"
		[ -z "$t2_CMD" ] || CMD="${CMD} ${t2_CMD}"
		[ "$ts_reset" = "1" ] && CMD="${CMD} --reset"
		CMD="${tailscale} ${CMD}"
	fi
	if [ "$ts_enable" = "2" ] ; then
		if [ -n "$t_CMD" ] ; then
			CMD="${tailscale} ${t_CMD}"
		else
			logger -t "【Tailscale】" "Custom startup parameters empty, using default parameter: up"
			CMD="${tailscale} up"
			nvram set tailscale_cmd="up"
		fi
	fi
}

# Ap dung lai flags (ts_dns/ts_route/ts_ssh/ts_host/...) qua "tailscale up"
# TREN DAEMON DANG CHAY, hoan toan KHONG kill/restart tailscaled. Day la
# ban chat binh thuong cua "tailscale up" - luon co the goi lai nhieu lan
# de doi cau hinh, khong can khoi dong lai daemon. Dung cho truong hop
# "chi doi setting roi Apply", tranh phai kill_ts + get_tag() (hit GitHub
# API kiem tra version) + tai lai binary khong can thiet.
HOT_RELOADED_MARKER="/tmp/.ts_hot_reloaded"

apply_ts_settings() {
	logger -t "【Tailscale】" "Chỉ đổi setting -> áp dụng lại qua 'tailscale up' (KHÔNG khởi động lại daemon)"
	build_up_cmd
	if [ -z "$CMD" ]; then
		logger -t "【Tailscale】" "CMD rỗng (ts_enable=$ts_enable không hợp lệ cho hot-reload) -> fallback full restart"
		stop_ts
		start_ts &
		return
	fi
	logger -t "【Tailscale】" "Chạy lại: ${CMD}"
	eval "$CMD >>/tmp/tailscale.log 2>&1" &
	sleep 3
	get_info
	touch "$HOT_RELOADED_MARKER"
}

start_ts() {
	# Neu stop_ts() vua hot-reload thanh cong (qua nhanh "Apply settings" o
	# duoi), marker nay se ton tai va daemon van dang song - bo qua toan bo
	# flow start lai tu dau (tranh spawn trung tailscaled / goi lai
	# get_tag() khong can thiet ngay sau khi vua hot-reload xong).
	if [ -f "$HOT_RELOADED_MARKER" ] && [ -n "$(pidof tailscaled)" ]; then
		rm -f "$HOT_RELOADED_MARKER"
		logger -t "【Tailscale】" "Đã hot-reload thành công ở bước stop trước đó -> bỏ qua start lại từ đầu"
		exit 0
	fi
	rm -f "$HOT_RELOADED_MARKER"

	[ "$ts_enable" = "0" ] && exit 1
	if [ "$ts_enable" = "3" ] ; then
		logger -t "【Tailscale】" "Clearing config files /etc/storage/tailscale/* ..."
		kill_ts
		rm -rf /etc/storage/tailscale/*
		nvram set tailscale_enable=0
		nvram set tailscale_login=""
		nvram set tailscale_info=""
		logger -t "【Tailscale】" "Config cleared"
		exit 0
	fi 
	logger -t "Tailscale" "Starting tailscale"
	sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check

	[ ! -f "$tailscaled" ] && extract_bundled_ts
	get_tag
	if [ -f "$tailscaled" ] ; then
		[ ! -x "$tailscaled" ] && chmod +x "$tailscaled"
		if ! "$tailscaled" -version >/dev/null 2>&1 ; then
			logger -t "【Tailscale】" "Program ${tailscaled} is incomplete!"
			rm -rf "$tailscaled"
		fi
	fi
	if [ ! -f "$tailscaled" ] ; then
		logger -t "【Tailscale】" "Main program ${tailscaled} not found, starting download..."
		[ -z "$tag" ] && tag="v1.78.1"
		dowload_ts "$tag"
	fi

	if [ ! -f "$tailscaled" ] ; then
		logger -t "【Tailscale】" "ERROR: Main program /tmp/tailscaled missing or download failed!"
		ts_restart x
		exit 1
	fi

	kill_ts
	[ ! -x "$tailscaled" ] && chmod +x "$tailscaled"
	path=$(dirname "$tailscaled")
	tailscale="${path}/tailscale"
	if [ ! -L "$tailscale" ] || [ "$(ls -l $tailscale | awk '{print $NF}')" != "$tailscaled" ] ; then
		ln -sf "$tailscaled" "$tailscale"
	fi

	if command -v timeout >/dev/null 2>&1; then
		timeout 8 "$tailscaled" --cleanup >/tmp/tailscale.log 2>&1
	else
		$tailscaled --cleanup >/tmp/tailscale.log 2>&1
	fi
	tdCMD="$tailscaled --state=/etc/storage/tailscale/lib/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock"
	logger -t "【Tailscale】" "Running main program $tdCMD"
	
	# TỐI ƯU CHO NEWIFI 3 (RAM 512MB)
	export GOMEMLIMIT=96MiB
	export GOGC=50
	
	eval "$tdCMD >>/tmp/tailscale.log 2>&1" &
	sleep 4
	
	pid_td=$(pidof tailscaled)
	if [ -n "$pid_td" ] ; then
		mem=$(grep -w VmRSS /proc/$pid_td/status 2>/dev/null | awk '{printf "%.1f MB", $2/1024}')
		logger -t "【Tailscale】" "Main program running successfully! Memory usage: ${mem:-unknown}"
		ts_restart o
		iptables -C INPUT -i tailscale0 -j ACCEPT 2>/dev/null
		if [ "$?" != 0 ] ; then
			iptables -I INPUT -i tailscale0 -j ACCEPT
		fi
	else
		logger -t "【Tailscale】" "Failed to run main program, auto-retry in 10 seconds"
		sleep 10
		ts_restart x
	fi

	CMD=""
	build_up_cmd

	logger -t "【Tailscale】" "Running sub-process ${CMD}"
	eval "$CMD >>/tmp/tailscale.log 2>&1" &
	sleep 4
	
	ts_keep
	exit 0
}

kill_ts() {
	rm -f /tmp/tailscale.log
	if [ -n "$(pidof tailscaled)" ]; then
		logger -t "【Tailscale】" "Process running, terminating..."

		# 1. Thu SIGTERM (graceful) truoc - cho daemon co co hoi tu dong
		#    dong socket/tun/state file sach se, tranh de lai state do dang.
		killall tailscaled >/dev/null 2>&1
		killall tailscale >/dev/null 2>&1

		# 2. Cho toi da 5s, kiem tra lai moi giay - KHONG duoc bo qua buoc
		#    nay (truoc day khong co, dan toi stop_ts() check pidof ngay
		#    sau do co the con thay process (chua kip chet), lam mat dong
		#    log "stopped successfully" du thuc te se chet ngay sau).
		tries=0
		while [ -n "$(pidof tailscaled)" ] && [ $tries -lt 5 ]; do
			sleep 1
			tries=$((tries + 1))
		done

		# 3. Neu SIGTERM khong an thua sau 5s, escalate len SIGKILL.
		if [ -n "$(pidof tailscaled)" ]; then
			logger -t "【Tailscale】" "SIGTERM không đủ, escalate sang SIGKILL"
			killall -9 tailscaled >/dev/null 2>&1
			killall -9 tailscale >/dev/null 2>&1
			sleep 1
		fi

		# 4. CHI chay --cleanup SAU KHI da xac nhan daemon chet han (khac
		#    voi ban goc: goi --cleanup TRUOC khi kill, luc daemon con song
		#    - --cleanup thiet ke de don rac SAU khi daemon da chet, goi
		#    luc con song de gay tranh chap lock tren state file/socket,
		#    khien lenh treo vo han (day chinh la nguyen nhan syslog chi
		#    thay dong "terminating..." ma khong bao gio thay dong ke tiep -
		#    script bi ket cung tai day, khong bao gio chay toi killall).
		#    Boc them "timeout" (neu busybox co ho tro) de phong ngua treo
		#    du da kill xong, vi mot so ban --cleanup van co the cho mang.
		if [ -f "$tailscaled" ]; then
			if command -v timeout >/dev/null 2>&1; then
				timeout 8 "$tailscaled" --cleanup >/dev/null 2>&1
			else
				"$tailscaled" --cleanup >/dev/null 2>&1
			fi
		fi
	fi
}

stop_ts() {
	# QUAN TRONG: services.c dinh nghia restart_tailscale() = stop_tailscale()
	# + start_tailscale() nhu 2 eval() TACH BIET (khong bao gio goi thang
	# case "restart" cua shell script nay - case do chi chay duoc khi tu
	# tay SSH goi "tailscale.sh restart"). Vi vay co che hot-reload PHAI
	# nam trong chinh stop_ts() nay moi co tac dung that qua WebUI Apply.
	#
	# Neu ts_enable=1 hoac 2 (start_tailscale() se duoc C goi lai NGAY SAU,
	# vi no check "if (tailscale_enable==1 || ==2)") VA daemon dang song
	# that -> day CHI la buoc 1 cua chu ky Apply, KHONG PHAI tat/reset that
	# -> thu hot-reload qua "tailscale up" TRUOC, hoan toan KHONG kill.
	if [ -n "$(pidof tailscaled)" ] && { [ "$ts_enable" = "1" ] || [ "$ts_enable" = "2" ]; }; then
		logger -t "【Tailscale】" "Apply settings (ts_enable=$ts_enable) + daemon đang sống -> hot-reload qua 'tailscale up', không kill daemon"
		apply_ts_settings
		return 0
	fi

	logger -t "【Tailscale】" "Stopping tailscale..."
	sed -Ei '/【Tailscaled】|^$/d' /tmp/script/_opt_script_check
	kill_ts
	iptables -D INPUT -i tailscale0 -j ACCEPT 2>/dev/null
	if [ -z "$(pidof tailscaled)" ]; then
		logger -t "【Tailscale】" "tailscale stopped successfully!"
	else
		logger -t "【Tailscale】" "CẢNH BÁO: tailscaled vẫn còn sống sau khi stop (có thể bị treo ở --cleanup hoặc process zombie)"
	fi
}

case $1 in
start)
	start_ts &
	;;
stop)
	stop_ts
	;;
restart)
	# Logic hot-reload (Apply settings vs tat/reset that) da nam san ben
	# trong stop_ts() va start_ts() (doc ts_enable runtime + marker), nen o
	# day chi can goi tuan tu binh thuong - ca 2 ham tu biet phai hot-reload
	# hay full restart.
	stop_ts
	start_ts &
	;;
update)
	update_ts &
	;;
*)
	echo "check"
	;;
esac
