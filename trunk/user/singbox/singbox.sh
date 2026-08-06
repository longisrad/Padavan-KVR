#!/bin/sh
# sing-box lifecycle manager for Padavan-KVR (NEWIFI3)

# Bổ sung /opt/bin, /opt/sbin (Entware) vào PATH
export PATH="/opt/sbin:/opt/bin:$PATH"

BIN_DIR="/tmp/sing-box"
BIN_PATH="$BIN_DIR/sing-box"
CFG_PATH="/etc/storage/singbox.conf"
WORK_DIR="/tmp/sing-box/work"
LOG_FILE="/tmp/singbox.log"
LOG_TAG="sing-box"
WATCHDOG_FILE="/tmp/script/_opt_script_check"
RULESET_DIR="/tmp/sing-box/rule-set"
SUB_CACHE="/tmp/sing-box/sub_raw.json"

# Cập nhật Subscription: file lưu mốc thời gian lần cập nhật gần nhất
LAST_SUB_UPDATE_FILE="/etc/storage/singbox_last_sub_update"
SUB_UPDATE_INTERVAL=259200
CRON_TAG="singbox_autoupdate"

# Giữ nguyên REPO của bạn
REPO="yourname/padavan-KVR"
GH_API="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="sing-box.bin"

# Tên asset jq tĩnh (mipsel)
JQ_ASSET_NAME="jq-mipsle.bin"
# ĐÃ SỬA: Đổi vị trí lưu jq sang /tmp RAM để KHÔNG làm tràn Flash /etc/storage
JQ_STORAGE_PATH="/tmp/sing-box/jq"

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof sing-box)" ]
}

# Tự động cắt ngắn log nếu vượt quá 300KB để tránh tràn RAM /tmp
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        size="$(wc -c < "$LOG_FILE" 2>/dev/null)"
        if [ -n "$size" ] && [ "$size" -gt 307200 ]; then
            tail -n 200 "$LOG_FILE" > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
            log "Log file truncated to prevent RAM exhaustion"
        fi
    fi
}

download_binary() {
    log "Downloading sing-box from ${REPO} latest release..."
    mkdir -p "$BIN_DIR"

    dl_url="$(curl -sk --connect-timeout 5 "$GH_API" 2>/dev/null \
        | grep "browser_download_url.*${ASSET_NAME}" \
        | cut -d'"' -f4 | head -n1)"

    if [ -z "$dl_url" ]; then
        log "Could not find ${ASSET_NAME} in latest release of ${REPO}"
        return 1
    fi

    curl -Lksfo "$BIN_PATH" --connect-timeout 10 --retry 2 --max-time 120 "$dl_url" \
        || wget --no-check-certificate -T 20 -t 2 -q -O "$BIN_PATH" "$dl_url"

    size="$(wc -c < "$BIN_PATH" 2>/dev/null)"
    if [ -z "$size" ] || [ "$size" -lt 1000000 ]; then
        log "Download failed or incomplete (size=${size:-0} bytes)"
        rm -f "$BIN_PATH"
        return 1
    fi

    chmod +x "$BIN_PATH"
    if ! "$BIN_PATH" version >/dev/null 2>&1 ; then
        log "Downloaded binary failed sanity check"
        rm -f "$BIN_PATH"
        return 1
    fi

    log "sing-box ready at $BIN_PATH"
    return 0
}

ensure_binary() {
    if [ -x "$BIN_PATH" ] && "$BIN_PATH" version >/dev/null 2>&1 ; then
        return 0
    fi
    rm -f "$BIN_PATH"
    download_binary
}

UI_DIR="/tmp/sing-box/ui"
UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"

ensure_dashboard() {
    # ĐÃ SỬA: Xóa bỏ file nén UI cũ trong /etc/storage nếu có để giải phóng bộ nhớ Flash bị tràn
    if [ -f "/etc/storage/singbox_ui.tar.gz" ]; then
        log "Cleaning up old UI archive from /etc/storage to free up Flash storage..."
        rm -f "/etc/storage/singbox_ui.tar.gz"
        [ -x /sbin/mtd_storage.sh ] && /sbin/mtd_storage.sh save >/dev/null 2>&1
    fi

    # 1. Đã có trong /tmp RAM -> Bỏ qua
    [ -f "$UI_DIR/index.html" ] && return 0

    # 2. Tải trực tiếp Dashboard về /tmp RAM
    log "Downloading Clash-compatible dashboard (metacubexd)..."
    mkdir -p "$UI_DIR"
    tmp_zip="/tmp/sing-box/ui.zip"

    curl -Lksfo "$tmp_zip" --connect-timeout 10 --retry 2 --max-time 90 "$UI_URL" \
        || wget --no-check-certificate -T 20 -t 2 -q -O "$tmp_zip" "$UI_URL"

    size="$(wc -c < "$tmp_zip" 2>/dev/null)"
    if [ -z "$size" ] || [ "$size" -lt 100000 ]; then
        log "Dashboard download failed - external_ui will stay empty"
        rm -f "$tmp_zip"
        return 1
    fi

    rm -rf /tmp/sing-box/_uiextract
    mkdir -p /tmp/sing-box/_uiextract
    unzip -q "$tmp_zip" -d /tmp/sing-box/_uiextract 2>/dev/null
    rm -f "$tmp_zip"

    extracted_dir="$(find /tmp/sing-box/_uiextract -maxdepth 1 -type d -name 'metacubexd-*' | head -n1)"
    if [ -z "$extracted_dir" ] || [ ! -f "$extracted_dir/index.html" ]; then
        log "Dashboard index.html not found"
        rm -rf /tmp/sing-box/_uiextract
        return 1
    fi

    mv "$extracted_dir"/* "$UI_DIR"/
    rm -rf /tmp/sing-box/_uiextract

    log "Dashboard ready at $UI_DIR"
    return 0
}

nv() {
    nvram get "$1" 2>/dev/null
}

JQ_BIN=""
have_jq() {
    [ -n "$JQ_BIN" ] && [ -x "$JQ_BIN" ] && return 0
    for p in "$JQ_STORAGE_PATH" /opt/bin/jq /opt/usr/bin/jq /usr/bin/jq /usr/sbin/jq jq; do
        resolved="$(command -v "$p" 2>/dev/null)"
        if [ -n "$resolved" ]; then
            JQ_BIN="$resolved"
            return 0
        fi
    done

    if download_jq; then
        JQ_BIN="$JQ_STORAGE_PATH"
        return 0
    fi

    return 1
}

download_jq() {
    log "Không tìm thấy jq trên máy -> đang thử tự tải bản build sẵn (${JQ_ASSET_NAME})..."

    dl_url="$(curl -sk --connect-timeout 5 "$GH_API" 2>/dev/null \
        | grep "browser_download_url.*${JQ_ASSET_NAME}" \
        | cut -d'"' -f4 | head -n1)"

    if [ -z "$dl_url" ]; then
        log "Release của ${REPO} chưa có asset ${JQ_ASSET_NAME} -> không tự tải được jq."
        return 1
    fi

    tmp_jq="/tmp/sing-box/jq_tmp"
    mkdir -p /tmp/sing-box
    curl -Lksfo "$tmp_jq" --connect-timeout 10 --retry 2 --max-time 60 "$dl_url" \
        || wget --no-check-certificate -T 20 -t 2 -q -O "$tmp_jq" "$dl_url"

    size="$(wc -c < "$tmp_jq" 2>/dev/null)"
    if [ -z "$size" ] || [ "$size" -lt 100000 ]; then
        log "Tải jq thất bại hoặc file quá nhỏ (size=${size:-0} bytes)"
        rm -f "$tmp_jq"
        return 1
    fi

    chmod +x "$tmp_jq"
    if ! "$tmp_jq" --version >/dev/null 2>&1; then
        log "Binary jq tải về không chạy được -> bỏ"
        rm -f "$tmp_jq"
        return 1
    fi

    # ĐÃ SỬA: Dời file jq sang /tmp RAM để không tràn Flash
    mv -f "$tmp_jq" "$JQ_STORAGE_PATH"
    chmod +x "$JQ_STORAGE_PATH"
    log "Đã tải jq vào $JQ_STORAGE_PATH ($size bytes)"
    return 0
}

# ----- Khối DNS theo singbox_dns_mode: 0=Direct 1=FakeIP 2=DoH -----
build_dns_block() {
    case "$1" in
        1)
            cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-remote", "address": "tls://8.8.8.8", "detour": "direct" },
      { "tag": "dns-fakeip", "address": "fakeip" }
    ],
    "fakeip": { "enabled": true, "inet4_range": "198.18.0.0/15" },
    "rules": [ { "query_type": ["A","AAAA"], "server": "dns-fakeip" } ],
    "independent_cache": true
  },
EOF
            ;;
        2)
            cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-remote", "address": "https://1.1.1.1/dns-query", "detour": "direct" },
      { "tag": "dns-direct", "address": "https://dns.google/dns-query", "detour": "direct" }
    ],
    "independent_cache": true
  },
EOF
            ;;
        *)
            cat <<-EOF
  "dns": {
    "servers": [ { "tag": "dns-direct", "address": "8.8.8.8", "detour": "direct" } ],
    "independent_cache": true
  },
EOF
            ;;
    esac
}

# ----- Route rules: bypass VN + AdBlock -----
build_route_block() {
    bypass_vn="$1"; adblock="$2"; final_tag="$3"
    rulesets=""
    rules=""

    if [ "$bypass_vn" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geosite-vn\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-vn.srs\", \"download_detour\": \"direct\" },
    { \"tag\": \"geoip-vn\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-vn.srs\", \"download_detour\": \"direct\" },
"
        rules="${rules}    { \"rule_set\": [\"geosite-vn\",\"geoip-vn\"], \"outbound\": \"direct\" },
"
    fi

    if [ "$adblock" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geosite-ads\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs\", \"download_detour\": \"direct\" },
"
        rules="${rules}    { \"rule_set\": \"geosite-ads\", \"outbound\": \"block\" },
"
    fi

    cat <<-EOF
  "route": {
    "rule_set": [
${rulesets%,
}
    ],
    "rules": [
${rules}    { "ip_is_private": true, "outbound": "direct" }
    ],
    "final": "${final_tag}",
    "auto_detect_interface": true
  },
EOF
}

# ----- Tải & gộp TẤT CẢ Sub trong singbox_sub_list -----
GROUP_DIR="/tmp/sing-box/groups"

fetch_all_groups() {
    sub_list_json="$(nv singbox_sub_list)"
    [ -z "$sub_list_json" ] && { log "Chưa có Subscription nào trong singbox_sub_list"; return 1; }

    if ! have_jq; then
        log "CANH BAO: thieu 'jq' -> khong thể tu dong gop nhom tu Subscription. Hãy cài jq (opkg install jq)."
        return 1
    fi

    count="$(echo "$sub_list_json" | "$JQ_BIN" 'length' 2>/dev/null)"
    case "$count" in ''|*[!0-9]*) log "singbox_sub_list không hợp lệ"; return 1 ;; esac
    [ "$count" -gt 0 ] || { log "Danh sách sub rỗng"; return 1; }

    rm -rf "$GROUP_DIR"; mkdir -p "$GROUP_DIR"
    : > "$GROUP_DIR/all_proxies.jsonl"
    : > "$GROUP_DIR/all_selectors.jsonl"
    echo "[]" > "$GROUP_DIR/group_tags.json"

    i=0
    while [ "$i" -lt "$count" ]; do
        entry="$(echo "$sub_list_json" | "$JQ_BIN" -c ".[$i]")"
        name="$(echo "$entry" | "$JQ_BIN" -r '.name // empty')"
        url="$(echo "$entry" | "$JQ_BIN" -r '.url // empty')"
        i=$((i + 1))
        [ -z "$name" ] && name="Group $i"
        [ -z "$url" ] && { log "Bỏ qua Sub #$i vì thiếu URL"; continue; }

        cache="$GROUP_DIR/sub_${i}.json"
        log "Đang tải sub '$name': $url"
        curl -Lksfo "$cache" --connect-timeout 10 --max-time 30 "$url" \
            || wget --no-check-certificate -T 15 -q -O "$cache" "$url"

        if ! "$JQ_BIN" -e '.outbounds' "$cache" >/dev/null 2>&1; then
            log "Sub '$name' không phải định dạng sing-box JSON hợp lệ (thiếu outbounds[]) -> bỏ qua"
            continue
        fi

        proxies="$("$JQ_BIN" -c --arg pfx "${name} - " '
            [ .outbounds[]
              | select(.type!="direct" and .type!="block" and .type!="dns" and .type!="selector" and .type!="urltest")
              | .tag = ($pfx + .tag) ]' "$cache" 2>/dev/null)"
        [ -z "$proxies" ] && proxies="[]"

        pcount="$(echo "$proxies" | "$JQ_BIN" 'length' 2>/dev/null)"
        case "$pcount" in ''|*[!0-9]*) pcount=0 ;; esac
        if [ "$pcount" -le 0 ]; then
            log "Sub '$name' không có proxy nào -> bỏ qua"
            continue
        fi

        echo "$proxies" | "$JQ_BIN" -c '.[]' >> "$GROUP_DIR/all_proxies.jsonl"

        group_outs="$(echo "$proxies" | "$JQ_BIN" -c '[.[].tag] + ["direct"]')"
        "$JQ_BIN" -nc --arg tag "$name" --argjson outs "$group_outs" \
            '{type:"selector", tag:$tag, outbounds:$outs}' >> "$GROUP_DIR/all_selectors.jsonl"

        "$JQ_BIN" -c --arg t "$name" '. + [$t]' "$GROUP_DIR/group_tags.json" > "$GROUP_DIR/group_tags.json.tmp" \
            && mv "$GROUP_DIR/group_tags.json.tmp" "$GROUP_DIR/group_tags.json"
    done

    total_groups="$("$JQ_BIN" 'length' "$GROUP_DIR/group_tags.json" 2>/dev/null)"
    case "$total_groups" in ''|*[!0-9]*) total_groups=0 ;; esac
    [ "$total_groups" -gt 0 ]
}

generate_config() {
    mode="$1"
    mem_limit="$(nv singbox_mem_limit)"
    [ -z "$mem_limit" ] && mem_limit="48MiB"
    bypass_vn="$(nv singbox_bypass_vn)"
    adblock="$(nv singbox_adblock)"
    dns_mode="$(nv singbox_dns_mode)"

    if [ "$mode" = "0" ]; then
        inbound_block='  "inbounds": [ { "type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": 7890 } ],'
    else
        inbound_block='  "inbounds": [ { "type": "tun", "tag": "tun-in", "interface_name": "singbox0", "address": ["172.19.0.1/30"], "mtu": 1500, "auto_route": true, "strict_route": true, "stack": "system", "sniff": true } ],'
    fi

    if fetch_all_groups; then
        final_tag="select"
        master_outs="$("$JQ_BIN" -c '. + ["direct"]' "$GROUP_DIR/group_tags.json")"
        selector_block=$("$JQ_BIN" -nc --argjson outs "$master_outs" '{type:"selector", tag:"select", outbounds:$outs}')
        selector_block="    ${selector_block},"
        group_selectors_body="$(sed 's/$/,/' "$GROUP_DIR/all_selectors.jsonl")"
        outbounds_body="$(sed 's/$/,/' "$GROUP_DIR/all_proxies.jsonl")"
    else
        log "Không gộp được nhóm nào từ Subscription -> chạy tạm ở chế độ Direct"
        final_tag="direct"
        selector_block=""
        group_selectors_body=""
        outbounds_body=""
    fi

    {
        echo "{"
        echo "  \"log\": { \"level\": \"info\", \"timestamp\": true },"
        echo "  \"experimental\": {"
        echo "    \"clash_api\": { \"external_controller\": \"0.0.0.0:9090\", \"external_ui\": \"${UI_DIR}\", \"secret\": \"admin\" },"
        echo "    \"cache_file\": { \"enabled\": true, \"path\": \"/tmp/sing-box/cache.db\" }"
        echo "  },"
        echo "$inbound_block"
        build_dns_block "$dns_mode"
        build_route_block "$bypass_vn" "$adblock" "$final_tag"
        echo "  \"outbounds\": ["
        echo "$selector_block"
        echo "$group_selectors_body"
        echo "$outbounds_body"
        echo "    { \"type\": \"direct\", \"tag\": \"direct\" },"
        echo "    { \"type\": \"block\", \"tag\": \"block\" }"
        echo "  ]"
        echo "}"
    } > "$CFG_PATH"

    log "Đã sinh config.json (mode=$mode, mem_limit=$mem_limit, bypass_vn=$bypass_vn, adblock=$adblock, dns_mode=$dns_mode, final=$final_tag)"
    [ -x /sbin/mtd_storage.sh ] && /sbin/mtd_storage.sh save >/dev/null 2>&1
}

install_cron() {
    if ! command -v cru >/dev/null 2>&1; then
        log "Không tìm thấy 'cru' trên firmware -> không thể lên lịch tự động cập nhật Sub"
        return 1
    fi
    cru d "$CRON_TAG" >/dev/null 2>&1
    cru a "$CRON_TAG" "0 4 * * * /usr/bin/singbox.sh update_sub"
    log "Đã bật lịch tự động kiểm tra/cập nhật Sub (mỗi ngày 4h sáng, thực thi thật sự mỗi 3 ngày)"
}

remove_cron() {
    command -v cru >/dev/null 2>&1 && cru d "$CRON_TAG" >/dev/null 2>&1
}

sync_cron_state() {
    if [ "$(nv singbox_auto_update)" = "1" ]; then
        install_cron
    else
        remove_cron
    fi
}

update_sub() {
    force="$1"
    now="$(date +%s 2>/dev/null)"
    case "$now" in ''|*[!0-9]*) now=0 ;; esac

    if [ "$force" != "force" ] && [ -f "$LAST_SUB_UPDATE_FILE" ]; then
        last="$(cat "$LAST_SUB_UPDATE_FILE" 2>/dev/null)"
        case "$last" in ''|*[!0-9]*) last=0 ;; esac
        elapsed=$(( now - last ))
        if [ "$last" -gt 0 ] && [ "$elapsed" -lt "$SUB_UPDATE_INTERVAL" ]; then
            log "update_sub: lần cập nhật gần nhất cách đây $((elapsed / 3600))h, chưa đủ 3 ngày -> bỏ qua"
            return 0
        fi
    fi

    sb_mode="$(nv singbox_mode)"
    case "$sb_mode" in
        0|1) ;;
        *)
            log "update_sub: chỉ hỗ trợ tự động gộp Sub ở Mode 1/2 (Mixed/TUN) - Mode 3 dùng JSON tùy chỉnh nên bỏ qua"
            return 1
            ;;
    esac

    log "===== Bắt đầu cập nhật nguồn Subscription ($([ "$force" = "force" ] && echo thủ công || echo tự động)) ====="

    if is_running; then
        restart
        ok=$?
    else
        generate_config "$sb_mode"
        ok=0
        log "update_sub: sing-box hiện chưa chạy, đã tái tạo sẵn config, sẽ áp dụng ở lần start kế tiếp"
    fi

    if [ "$ok" = "0" ]; then
        echo "$now" > "$LAST_SUB_UPDATE_FILE"
        log "===== Cập nhật Subscription hoàn tất ====="
    else
        log "===== Cập nhật Subscription THẤT BẠI (restart lỗi) - giữ nguyên mốc thời gian cũ để thử lại lần sau ====="
    fi
    return "$ok"
}

ensure_config() {
    sb_mode="$(nv singbox_mode)"
    case "$sb_mode" in
        0|1)
            generate_config "$sb_mode"
            ;;
        2)
            if [ ! -s "$CFG_PATH" ]; then
                log "Mode 3 (Custom JSON) nhưng $CFG_PATH rỗng - hãy dán config vào ô Raw JSON trên webui rồi Apply lại."
            fi
            ;;
        *)
            if [ ! -s "$CFG_PATH" ]; then
                cat > "$CFG_PATH" <<-EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [ { "type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": 7890 } ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
                log "Generated placeholder config at $CFG_PATH"
                [ -x /sbin/mtd_storage.sh ] && /sbin/mtd_storage.sh save >/dev/null 2>&1
            fi
            ;;
    esac
}

install_watchdog() {
    [ ! -f "$WATCHDOG_FILE" ] && return
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
    cat >> "$WATCHDOG_FILE" <<-EOF
[ -z "\`pidof sing-box\`" ] && $0 start #${LOG_TAG}_watchdog
	EOF
}

remove_watchdog() {
    [ -f "$WATCHDOG_FILE" ] && sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
}

start() {
    if [ "$(nv singbox_enable)" != "1" ]; then
        log "singbox_enable=0 -> khong khoi dong, chuyen sang stop()"
        stop
        return 0
    fi

    if is_running; then
        log "Already running, skip"
        return 0
    fi

    log "Starting..."
    rotate_log
    mkdir -p "$WORK_DIR"

    if ! ensure_binary; then
        log "Cannot start: no working binary"
        return 1
    fi

    ensure_dashboard
    ensure_config

    mem_limit="$(nv singbox_mem_limit)"
    [ -z "$mem_limit" ] && mem_limit="48MiB"
    export GOMEMLIMIT="$mem_limit"
    export GOGC=30

    cd "$WORK_DIR" && "$BIN_PATH" run -c "$CFG_PATH" >> "$LOG_FILE" 2>&1 &

    sleep 2
    if ! is_running; then
        log "Process exited immediately after start - check config syntax"
        return 1
    fi
    log "Process started (PID $(pidof sing-box))"

    install_watchdog
    sync_cron_state
    return 0
}

stop() {
    log "Stopping..."
    remove_watchdog
    remove_cron

    killall sing-box 2>/dev/null

    tries=0
    while is_running && [ $tries -lt 5 ]; do
        sleep 1
        tries=$((tries + 1))
    done

    if is_running; then
        log "Force killing remaining sing-box process..."
        killall -9 sing-box 2>/dev/null
    fi

    log "Stopped"
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if is_running; then
        echo "running"
    else
        echo "stopped"
    fi
}

case "$1" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    status)     status ;;
    update_sub) rotate_log; update_sub "$2" ;;
    *) echo "Usage: $0 {start|stop|restart|status|update_sub [force]}" ;;
esac
