#!/bin/sh
# ==============================================================================
# sing-box lifecycle manager for Newifi 3 D2 (MT7621AT - HYBRID Edition)
# TCP -> REDIRECT (7892) | UDP -> TPROXY (7893) | DNS -> 5353 / AGH -> 5354
# ==============================================================================

export PATH="/opt/sbin:/opt/bin:$PATH"

BIN_DIR="/tmp/sing-box"
BIN_PATH="$BIN_DIR/sing-box"
CFG_PATH="/etc/storage/singbox.conf"
CFG_MARKER="/tmp/sing-box/singbox.conf.autogen"
LAST_MODE_FILE="/tmp/sing-box/.last_mode_memlimit"
HOT_RELOADED_MARKER="/tmp/sing-box/.hot_reloaded"
WORK_DIR="/tmp/sing-box/work"
LOG_FILE="/tmp/singbox.log"
LOG_TAG="sing-box"
WATCHDOG_FILE="/tmp/script/_opt_script_check"
FORCE_FETCH_MARKER="/tmp/sing-box/.force_fetch"

# Ưu tiên script trong /etc/storage (ghi được), fallback về /etc_ro (ROM)
if [ -x "/etc/storage/singbox_route.sh" ]; then
    ROUTE_SCRIPT="/etc/storage/singbox_route.sh"
elif [ -x "/etc_ro/singbox/singbox_route.sh" ]; then
    ROUTE_SCRIPT="/etc_ro/singbox/singbox_route.sh"
else
    ROUTE_SCRIPT="/etc/storage/singbox_route.sh"
fi

LAST_SUB_UPDATE_FILE="/etc/storage/singbox_last_sub_update"
SUB_UPDATE_INTERVAL=259200
CRON_TAG="singbox_autoupdate"

CRON_FILE="/etc/storage/cron/crontabs/$(nvram get http_username 2>/dev/null)"
[ -z "$CRON_FILE" ] || [ ! -f "$CRON_FILE" ] && CRON_FILE="/etc/storage/cron/crontabs/admin"

REPO="shtorm-7/sing-box-extended"
GH_API="https://api.github.com/repos/${REPO}/releases/latest"
JQ_BIN="/usr/bin/jq"
ASSET_NAME="linux-mipsle-softfloat"

log() { logger -t "$LOG_TAG" "$1"; }
is_running() { [ -n "$(pidof sing-box)" ]; }
nv() { nvram get "$1" 2>/dev/null; }
have_jq() { [ -x "$JQ_BIN" ]; }

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
    log "Đang tải sing-box từ ${REPO} về RAM (/tmp/sing-box)..."
    mkdir -p "$BIN_DIR"
    dl_url="$(curl -sk --connect-timeout 4 "$GH_API" 2>/dev/null | grep -E "browser_download_url.*${ASSET_NAME}\.tar\.gz" | cut -d'"' -f4 | head -n1)"
    [ -z "$dl_url" ] && { log "Không tìm thấy asset ${ASSET_NAME}"; return 1; }

    tmp_file="/tmp/sing-box/download_sb.tmp"
    curl -Lksfo "$tmp_file" --connect-timeout 5 --retry 2 --max-time 90 "$dl_url" || wget --no-check-certificate -T 15 -t 2 -q -O "$tmp_file" "$dl_url"
    size="$(wc -c < "$tmp_file" 2>/dev/null)"
    [ -z "$size" ] || [ "$size" -lt 100000 ] && { log "Tải sing-box thất bại"; rm -f "$tmp_file"; return 1; }

    tar -xzf "$tmp_file" -C "$BIN_DIR/" 2>/dev/null
    rm -f "$tmp_file"
    extracted="$(find "$BIN_DIR" -type f -name "sing-box*" ! -name "*.tmp" | head -n1)"
    [ -n "$extracted" ] && mv -f "$extracted" "$BIN_PATH"
    find "$BIN_DIR" -mindepth 1 -maxdepth 1 -type d -name "sing-box-*" -exec rm -rf {} + 2>/dev/null

    chmod +x "$BIN_PATH"
    "$BIN_PATH" version >/dev/null 2>&1 || { log "Binary sing-box bị lỗi!"; rm -f "$BIN_PATH"; return 1; }
    log "sing-box đã sẵn sàng trên RAM: $BIN_PATH"
    return 0
}

ensure_binary() {
    for p in /usr/bin/sing-box /usr/sbin/sing-box /opt/bin/sing-box; do
        if [ -x "$p" ] && "$p" version >/dev/null 2>&1; then
            BIN_PATH="$p"; return 0
        fi
    done
    [ -x "$BIN_PATH" ] && "$BIN_PATH" version >/dev/null 2>&1 && return 0
    rm -f "$BIN_PATH"
    download_binary
}

UI_DIR="/tmp/sing-box/ui"
UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"

ensure_dashboard() {
    rm -f "/etc/storage/singbox_ui.tar.gz" 2>/dev/null
    [ -f "$UI_DIR/index.html" ] && return 0
    mkdir -p "$UI_DIR"
    tmp_zip="/tmp/sing-box/ui.zip"
    curl -Lksfo "$tmp_zip" --connect-timeout 5 --retry 2 --max-time 60 "$UI_URL" || wget --no-check-certificate -T 15 -t 2 -q -O "$tmp_zip" "$UI_URL"
    size="$(wc -c < "$tmp_zip" 2>/dev/null)"
    [ -z "$size" ] || [ "$size" -lt 100000 ] && { rm -f "$tmp_zip"; return 1; }

    rm -rf /tmp/sing-box/_uiextract; mkdir -p /tmp/sing-box/_uiextract
    unzip -q "$tmp_zip" -d /tmp/sing-box/_uiextract 2>/dev/null; rm -f "$tmp_zip"
    extracted_dir="$(find /tmp/sing-box/_uiextract -maxdepth 1 -type d -name 'metacubexd-*' | head -n1)"
    [ -n "$extracted_dir" ] && [ -f "$extracted_dir/index.html" ] && mv "$extracted_dir"/* "$UI_DIR"/
    rm -rf /tmp/sing-box/_uiextract
    return 0
}

ensure_converter() {
    CONVERTER_PATH="/tmp/sing-box/converter.lua"
    if [ ! -f "$CONVERTER_PATH" ]; then
        if [ -f "/etc_ro/singbox/converter.lua" ]; then
            cp -f "/etc_ro/singbox/converter.lua" "$CONVERTER_PATH"
        else
            curl -Lksfo "$CONVERTER_PATH" --connect-timeout 5 "https://raw.githubusercontent.com/Sophiedevops/singbox-padavan-easy-crawler-2/main/converter.lua"
        fi
    fi
}

build_dns_block() {
    dns_final_detour="$1"
    dns_mode="$2"
    agh_dns_bypass="$3"
    dns_redirect="$4"
    rt_mode="$5"
    [ -z "$dns_final_detour" ] && dns_final_detour="direct"
    [ -z "$dns_mode" ] && dns_mode="1"
    [ -z "$agh_dns_bypass" ] && agh_dns_bypass="0"
    [ -z "$dns_redirect" ] && dns_redirect="0"

    agh_rule=""
    agh_rule_bare=""
    if [ "$agh_dns_bypass" = "1" ]; then
        case "$dns_mode" in
            0) agh_rule_bare='      { "inbound": "dns-in-agh", "server": "dns-direct" }' ;;
            2) agh_rule_bare='      { "inbound": "dns-in-agh", "server": "dns-doh" }' ;;
            *) agh_rule='      { "inbound": "dns-in-agh", "server": "dns-remote" },
' ;;
        esac
    fi

    dns_agh_server=""
    dns_agh_rule_bare=""
    if [ "$dns_redirect" = "1" ] && [ "$rt_mode" = "1" ]; then
        dns_agh_server='      { "tag": "dns-agh", "type": "udp", "server": "127.0.0.1", "server_port": 5335 },
'
        dns_agh_rule_bare='      { "inbound": "dns-in", "server": "dns-agh" }'
    fi

    rules_02=""
    if [ -n "$dns_agh_rule_bare" ] && [ -n "$agh_rule_bare" ]; then
        rules_02="${dns_agh_rule_bare},
${agh_rule_bare}
"
    elif [ -n "$dns_agh_rule_bare" ]; then
        rules_02="${dns_agh_rule_bare}
"
    elif [ -n "$agh_rule_bare" ]; then
        rules_02="${agh_rule_bare}
"
    fi

    case "$dns_mode" in
    0)
        cat <<-EOF
  "dns": {
    "servers": [
${dns_agh_server}      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
${rules_02}    ],
    "final": "dns-direct",
    "independent_cache": true
  },
EOF
        ;;
    2)
        cat <<-EOF
  "dns": {
    "servers": [
${dns_agh_server}      { "tag": "dns-doh", "type": "https", "server": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
${rules_02}    ],
    "final": "dns-doh",
    "independent_cache": true
  },
EOF
        ;;
    *)
        # Đổi type từ "tls" (port 853) sang "https" (DoH port 443) chống chặn tuyệt đối
        cat <<-EOF
  "dns": {
    "servers": [
${dns_agh_server}      { "tag": "dns-remote", "type": "https", "server": "1.1.1.1", "detour": "${dns_final_detour}" },
      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" },
      { "tag": "dns-fakeip", "type": "fakeip", "inet4_range": "198.18.0.0/15" }
    ],
    "rules": [
${dns_agh_rule}${agh_rule}      { "domain_suffix": ["githubusercontent.com", "github.com", "adguard.com", "adguard-dns.com"], "server": "dns-direct" },
      { "query_type": ["A", "AAAA"], "server": "dns-fakeip" }
    ],
    "final": "dns-remote",
    "independent_cache": true
  },
EOF
        ;;
    esac
}

build_route_block() {
    bypass_vn="$1"; adblock="$2"; final_tag="$3"; rt_mode="$4"; dns_mode="$5"; ts_enable="$6"; agh_dns_bypass="$7"
    rulesets=""
    rules=""

    ts_route_rule=""
    if [ "$ts_enable" = "1" ]; then
        ts_route_rule='      { "ip_cidr": ["100.64.0.0/10", "fd7a:115c:a1e0::/48"], "outbound": "ts-ep" },
'
    fi

    case "$dns_mode" in
    2) default_resolver_tag="dns-doh" ;;
    *) default_resolver_tag="dns-direct" ;;
    esac

    agh_sniff=""
    [ "$agh_dns_bypass" = "1" ] && agh_sniff='      { "inbound": "dns-in-agh", "action": "sniff" },
'

    if [ "$rt_mode" = "0" ]; then
        sniff_rule="      { \"inbound\": \"mixed-in\", \"action\": \"sniff\" },
${agh_sniff}"
    else
        # Sniff cả redirect-in (TCP), tproxy-in (UDP), và dns-in
        sniff_rule="      { \"inbound\": \"redirect-in\", \"action\": \"sniff\" },
      { \"inbound\": \"tproxy-in\", \"action\": \"sniff\" },
      { \"inbound\": \"dns-in\", \"action\": \"sniff\" },
${agh_sniff}"
    fi

    if [ "$bypass_vn" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geoip-vn\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://testingcf.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-vn.srs\", \"download_detour\": \"direct\" },
"
        rules="${rules}    { \"rule_set\": \"geoip-vn\", \"outbound\": \"direct\" },
"
    fi

    if [ "$adblock" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geosite-ads\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://testingcf.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-category-ads-all.srs\", \"download_detour\": \"direct\" },
"
        rules="${rules}    { \"rule_set\": \"geosite-ads\", \"outbound\": \"block\" },
"
    fi

    # Tắt auto_detect_interface để tránh lỗi bind ifindex trên Kernel MIPS Padavan
    cat <<-EOF
  "route": {
    "rule_set": [
${rulesets%,
}
    ],
    "rules": [
${sniff_rule}      { "protocol": "dns", "action": "hijack-dns" },
${ts_route_rule}${rules}      { "ip_is_private": true, "outbound": "direct" }
    ],
    "final": "${final_tag}",
    "auto_detect_interface": false,
    "default_mark": 255,
    "default_domain_resolver": "${default_resolver_tag}"
  },
EOF
}

GROUP_DIR="/tmp/sing-box/groups"

fetch_all_groups() {
    SUB_FILE=""
    if [ -s "/etc/storage/scripts/singbox_sub.json" ]; then
        SUB_FILE="/etc/storage/scripts/singbox_sub.json"
    elif [ -s "/etc/storage/singbox_sub.json" ]; then
        SUB_FILE="/etc/storage/singbox_sub.json"
    fi

    if [ -n "$SUB_FILE" ]; then
        sub_list_json="$(cat "$SUB_FILE")"
    else
        sub_list_json="$(nv singbox_sub_list)"
    fi
	
    [ -z "$sub_list_json" ] && { log "Chưa cấu hình Subscription nào"; return 1; }
    have_jq || { log "LỖI: không tìm thấy 'jq' tại /usr/bin/jq."; return 1; }

    sub_list_json="$(echo "$sub_list_json" | "$JQ_BIN" -c '.' 2>/dev/null)"
    [ -z "$sub_list_json" ] && return 1

    fetch_force=0
    if [ -f "$FORCE_FETCH_MARKER" ]; then
        fetch_force=1
        rm -f "$FORCE_FETCH_MARKER"
    fi
    sub_hash="$(echo "$sub_list_json" | md5sum 2>/dev/null | cut -d' ' -f1)"
    if [ "$fetch_force" != "1" ] && [ -s "$GROUP_DIR/all_proxies.jsonl" ] && [ -f "$GROUP_DIR/.sub_hash" ] \
        && [ "$(cat "$GROUP_DIR/.sub_hash" 2>/dev/null)" = "$sub_hash" ] && [ -n "$sub_hash" ]; then
        cached_total="$("$JQ_BIN" 'length' "$GROUP_DIR/group_tags.json" 2>/dev/null)"
        case "$cached_total" in ''|*[!0-9]*) cached_total=0 ;; esac
        if [ "$cached_total" -gt 0 ]; then
            log "Dùng lại $cached_total nhóm Proxy đã cache"
            return 0
        fi
    fi

    count="$(echo "$sub_list_json" | "$JQ_BIN" 'length' 2>/dev/null)"
    case "$count" in ''|*[!0-9]*) return 1 ;; esac
    [ "$count" -gt 0 ] || return 1

    rm -rf "$GROUP_DIR"; mkdir -p "$GROUP_DIR"
    : > "$GROUP_DIR/all_proxies.jsonl"
    : > "$GROUP_DIR/all_selectors.jsonl"
    echo "[]" > "$GROUP_DIR/group_tags.json"

    i=0
    while [ "$i" -lt "$count" ]; do
        entry="$(echo "$sub_list_json" | "$JQ_BIN" -c ".[$i]")"
        enabled="$(echo "$entry" | "$JQ_BIN" -r '.enabled // true')"
        name="$(echo "$entry" | "$JQ_BIN" -r '.name // empty')"
        url="$(echo "$entry" | "$JQ_BIN" -r '.url // empty')"
        i=$((i + 1))

        [ "$enabled" = "false" ] || [ "$enabled" = "0" ] && continue
        [ -z "$name" ] && name="Group $i"
        [ -z "$url" ] && continue

        cache="$GROUP_DIR/sub_${i}.json"
        log "Đang tải sub '$name': $url"
        curl -Lksfo "$cache" --connect-timeout 4 --max-time 12 "$url" || wget --no-check-certificate -T 10 -q -O "$cache" "$url"

        if ! "$JQ_BIN" -e '.outbounds' "$cache" >/dev/null 2>&1; then
            ensure_converter
            if [ -f "/tmp/sing-box/converter.lua" ] && which lua >/dev/null 2>&1; then
                cp -f "$cache" /tmp/sing-box/subs_raw.txt
                cd /tmp/sing-box && lua converter.lua >/dev/null 2>&1
                if [ -s "/tmp/sing-box/all_nodes.json" ]; then
                    echo '{"outbounds":' > "$cache"
                    cat /tmp/sing-box/all_nodes.json >> "$cache"
                    echo '}' >> "$cache"
                    rm -f /tmp/sing-box/subs_raw.txt /tmp/sing-box/all_nodes.json
                fi
            fi
        fi

        ! "$JQ_BIN" -e '.outbounds' "$cache" >/dev/null 2>&1 && continue

        proxies="$("$JQ_BIN" -c --arg pfx "${name} - " '
            [ .outbounds[]
              | select(.type!="direct" and .type!="block" and .type!="dns" and .type!="selector" and .type!="urltest")
              | .tag = ($pfx + .tag) ][0:300]' "$cache" 2>/dev/null)"
        [ -z "$proxies" ] && proxies="[]"

        pcount="$(echo "$proxies" | "$JQ_BIN" 'length' 2>/dev/null)"
        case "$pcount" in ''|*[!0-9]*) pcount=0 ;; esac
        [ "$pcount" -le 0 ] && continue

        echo "$proxies" | "$JQ_BIN" -c '.[]' >> "$GROUP_DIR/all_proxies.jsonl"
        group_outs="$(echo "$proxies" | "$JQ_BIN" -c '[.[].tag]')"
        "$JQ_BIN" -nc --arg tag "$name" --argjson outs "$group_outs" \
            '{type:"urltest", tag:$tag, outbounds:$outs, url:"http://www.gstatic.com/generate_204", interval:"5m", tolerance:50}' >> "$GROUP_DIR/all_selectors.jsonl"

        "$JQ_BIN" -c --arg t "$name" '. + [$t]' "$GROUP_DIR/group_tags.json" > "$GROUP_DIR/group_tags.json.tmp" \
            && mv "$GROUP_DIR/group_tags.json.tmp" "$GROUP_DIR/group_tags.json"
    done

    total_groups="$("$JQ_BIN" 'length' "$GROUP_DIR/group_tags.json" 2>/dev/null)"
    case "$total_groups" in ''|*[!0-9]*) total_groups=0 ;; esac
    [ "$total_groups" -gt 0 ] && [ -n "$sub_hash" ] && echo "$sub_hash" > "$GROUP_DIR/.sub_hash"
    [ "$total_groups" -gt 0 ]
}

build_endpoints_block() {
    [ "$1" != "1" ] && return 0
    have_jq || return 0

    ts_authkey="$(nv singbox_ts_authkey)"
    ts_hostname="$(nv singbox_ts_hostname)"
    ts_control_url="$(nv singbox_ts_control_url)"
    ts_exit_node="$(nv singbox_ts_exit_node)"

    [ "$(nv singbox_ts_accept_routes)" = "1" ] && ts_ar=true || ts_ar=false
    [ "$(nv singbox_ts_ephemeral)" = "1" ] && ts_eph=true || ts_eph=false
    [ "$(nv singbox_ts_exit_node_allow_lan)" = "1" ] && ts_exl=true || ts_exl=false
    [ "$(nv singbox_ts_advertise_exit_node)" = "1" ] && ts_advexit=true || ts_advexit=false
    [ "$(nv singbox_ts_ssh_server)" = "1" ] && ts_sshv=true || ts_sshv=false

    sb_ver="$("$BIN_PATH" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    [ -n "$sb_ver" ] && [ "$(printf '%s\n%s\n' "1.14.0" "$sb_ver" | sort -V | tail -n1)" = "$sb_ver" ] && ts_ssh_supported=true || ts_ssh_supported=false

    adv_routes_json="$(echo "$(nv singbox_ts_advertise_routes)" | "$JQ_BIN" -R -c 'split(",") | map(gsub("^[ \t]+|[ \t]+$";"")) | map(select(length>0))' 2>/dev/null)"
    [ -z "$adv_routes_json" ] && adv_routes_json="[]"

    adv_tags_json="$(echo "$(nv singbox_ts_advertise_tags)" | "$JQ_BIN" -R -c 'split(",") | map(gsub("^[ \t]+|[ \t]+$";"")) | map(select(length>0))' 2>/dev/null)"
    [ -z "$adv_tags_json" ] && adv_tags_json="[]"

    ts_endpoint_json="$("$JQ_BIN" -nc \
        --arg authkey "$ts_authkey" \
        --arg hostname "$ts_hostname" \
        --arg control_url "$ts_control_url" \
        --arg exit_node "$ts_exit_node" \
        --argjson accept_routes "$ts_ar" \
        --argjson ephemeral "$ts_eph" \
        --argjson exit_node_allow_lan_access "$ts_exl" \
        --argjson advertise_exit_node "$ts_advexit" \
        --argjson ssh_server "$ts_sshv" \
        --argjson ssh_supported "$ts_ssh_supported" \
        --argjson advertise_routes "$adv_routes_json" \
        --argjson advertise_tags "$adv_tags_json" \
        '{
            type: "tailscale",
            tag: "ts-ep",
            state_directory: "/etc/storage/tailscale-sb",
            system_interface: false,
            accept_routes: $accept_routes,
            ephemeral: $ephemeral,
            exit_node_allow_lan_access: $exit_node_allow_lan_access,
            advertise_exit_node: $advertise_exit_node
        }
        + (if $ssh_supported then {ssh_server: $ssh_server} else {} end)
        + (if $authkey != "" then {auth_key: $authkey} else {} end)
        + (if $hostname != "" then {hostname: $hostname} else {} end)
        + (if $control_url != "" then {control_url: $control_url} else {} end)
        + (if $exit_node != "" then {exit_node: $exit_node} else {} end)
        + (if ($advertise_routes|length) > 0 then {advertise_routes: $advertise_routes} else {} end)
        + (if ($advertise_tags|length) > 0 then {advertise_tags: $advertise_tags} else {} end)
        ' 2>/dev/null)"

    [ -n "$ts_endpoint_json" ] && echo "  \"endpoints\": [ ${ts_endpoint_json} ],"
}

generate_config() {
    mode="$1"
    ts_enable="$(nv singbox_ts_enable)"; [ -z "$ts_enable" ] && ts_enable="0"
    mem_limit="$(nv singbox_mem_limit)"; [ -z "$mem_limit" ] && mem_limit="192MiB"
    bypass_vn="$(nv singbox_bypass_vn)"; [ -z "$bypass_vn" ] && bypass_vn="0"
    adblock="$(nv singbox_adblock)"; [ -z "$adblock" ] && adblock="0"
    dns_mode="$(nv singbox_dns_mode)"; [ -z "$dns_mode" ] && dns_mode="1"
    agh_dns_bypass="$(nv singbox_agh_dns_bypass)"; [ -z "$agh_dns_bypass" ] && agh_dns_bypass="0"

    if [ "$mode" = "0" ] && [ "$dns_mode" = "1" ]; then
        dns_mode="0"
    fi

    agh_dns_in=""
    if [ "$agh_dns_bypass" = "1" ]; then
        agh_dns_in=',
          { "type": "direct", "tag": "dns-in-agh", "listen": "127.0.0.1", "listen_port": 5354 }'
    fi

    # CẤU HÌNH HYBRID: TCP đi qua redirect-in (7892), UDP đi qua tproxy-in (7893)
    if [ "$mode" = "0" ]; then
        inbound_block="  \"inbounds\": [
          { \"type\": \"mixed\", \"tag\": \"mixed-in\", \"listen\": \"0.0.0.0\", \"listen_port\": 7890 }${agh_dns_in}
        ],"
    else
        inbound_block="  \"inbounds\": [ 
          { \"type\": \"redirect\", \"tag\": \"redirect-in\", \"listen\": \"0.0.0.0\", \"listen_port\": 7892 },
          { \"type\": \"tproxy\", \"tag\": \"tproxy-in\", \"listen\": \"0.0.0.0\", \"listen_port\": 7893 },
          { \"type\": \"direct\", \"tag\": \"dns-in\", \"listen\": \"0.0.0.0\", \"listen_port\": 5353 }${agh_dns_in}
        ],"
    fi

    if fetch_all_groups; then
        final_tag="select"
        master_outs="$("$JQ_BIN" -c '. + ["direct"]' "$GROUP_DIR/group_tags.json")"
        selector_block=$("$JQ_BIN" -nc --argjson outs "$master_outs" '{type:"selector", tag:"select", outbounds:$outs}')
        selector_block="    ${selector_block},"
        group_selectors_body="$(sed 's/$/,/' "$GROUP_DIR/all_selectors.jsonl")"
        outbounds_body="$(sed 's/$/,/' "$GROUP_DIR/all_proxies.jsonl")"
    else
        final_tag="direct"
        selector_block=""
        group_selectors_body=""
        outbounds_body=""
    fi

    {
        echo "{"
        echo "  \"log\": { \"level\": \"info\", \"timestamp\": true },"
        echo "  \"experimental\": {"
        echo "    \"clash_api\": { \"external_controller\": \"0.0.0.0:9090\", \"external_ui\": \"${UI_DIR}\", \"secret\": \"\" },"
        echo "    \"cache_file\": { \"enabled\": true, \"path\": \"/tmp/sing-box/cache.db\", \"store_fakeip\": true }"
        echo "  },"
        echo "$inbound_block"
        build_endpoints_block "$ts_enable"
        build_dns_block "$final_tag" "$dns_mode" "$agh_dns_bypass" "$(nv singbox_dns_redirect)" "$mode"
        build_route_block "$bypass_vn" "$adblock" "$final_tag" "$mode" "$dns_mode" "$ts_enable" "$agh_dns_bypass"
        echo "  \"outbounds\": ["
        echo "$selector_block"
        echo "$group_selectors_body"
        echo "$outbounds_body"
        echo "    { \"type\": \"direct\", \"tag\": \"direct\" },"
        echo "    { \"type\": \"block\", \"tag\": \"block\" }"
        echo "  ]"
        echo "}"
    } > "$CFG_PATH"

    mkdir -p "$(dirname "$CFG_MARKER")" 2>/dev/null
    touch "$CFG_MARKER"
    log "Đã sinh config.json HYBRID (mode=$mode, dns_mode=$dns_mode, final=$final_tag)"
}

apply_iptables_mode() {
    sb_mode="$(nv singbox_mode)"
    if [ "$sb_mode" = "1" ]; then
        if [ -x "$ROUTE_SCRIPT" ]; then
            log "Gọi script định tuyến ($ROUTE_SCRIPT start)..."
            "$ROUTE_SCRIPT" start || return 1
        else
            log "LỖI: Không tìm thấy file $ROUTE_SCRIPT"
            return 1
        fi
    else
        clean_iptables
    fi
    return 0
}

clean_iptables() {
    [ -x "$ROUTE_SCRIPT" ] && "$ROUTE_SCRIPT" stop
}

install_cron() {
    cron_cmd="0 4 * * * /usr/bin/singbox.sh update_sub #$CRON_TAG"
    mkdir -p "$(dirname "$CRON_FILE")" 2>/dev/null
    touch "$CRON_FILE" 2>/dev/null
    sed -i "/$CRON_TAG/d" "$CRON_FILE" 2>/dev/null
    echo "$cron_cmd" >> "$CRON_FILE"
    killall -HUP crond 2>/dev/null
}

remove_cron() {
    if [ -f "$CRON_FILE" ]; then
        sed -i "/$CRON_TAG/d" "$CRON_FILE" 2>/dev/null
        killall -HUP crond 2>/dev/null
    fi
}

sync_cron_state() {
    [ "$(nv singbox_auto_update)" = "1" ] && install_cron || remove_cron
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
            return 0
        fi
    fi

    sb_mode="$(nv singbox_mode)"
    [ "$sb_mode" != "0" ] && [ "$sb_mode" != "1" ] && return 1

    mkdir -p "$(dirname "$FORCE_FETCH_MARKER")" 2>/dev/null
    touch "$FORCE_FETCH_MARKER"
    restart
    ok=$?
    [ "$ok" = "0" ] && echo "$now" > "$LAST_SUB_UPDATE_FILE"
    return "$ok"
}

ensure_config() {
    sb_mode="$(nv singbox_mode)"
    case "$sb_mode" in
        0|1) generate_config "$sb_mode" ;;
        *)
            if [ ! -s "$CFG_PATH" ]; then
                cat > "$CFG_PATH" <<-EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [ { "type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": 7890 } ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
            fi
            ;;
    esac
}

fix_resolv_conf() {
    # Gỡ 127.0.0.1 và tự động thêm Fallback DNS nếu file bị rỗng
    if [ -f /etc/resolv.conf ]; then
        sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.conf
        if ! grep -q "^nameserver" /etc/resolv.conf; then
            echo "nameserver 1.1.1.1" > /etc/resolv.conf
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        fi
    fi
}

install_post_iptables_hook() {
    post_ipt_file="/etc/storage/post_iptables_script.sh"
    if [ ! -f "$post_ipt_file" ]; then
        echo '#!/bin/sh' > "$post_ipt_file"
        chmod +x "$post_ipt_file"
    fi
    sed -i '/singbox\.sh/d' "$post_ipt_file" 2>/dev/null
    cat >> "$post_ipt_file" <<-EOF

### sing-box: Re-apply routing khi interface/firewall thay doi
[ -x /usr/bin/singbox.sh ] && /usr/bin/singbox.sh reapply_iptables
	EOF
    chmod +x "$post_ipt_file" 2>/dev/null
}

install_watchdog() {
    [ ! -f "$WATCHDOG_FILE" ] && return
    sed -i '/sing-box/d' "$WATCHDOG_FILE" 2>/dev/null
    cat >> "$WATCHDOG_FILE" <<-EOF
[ -z "\`pidof sing-box\`" ] && $0 start #sing-box_watchdog
$0 check_ts_conflict #sing-box_watchdog
	EOF
}

remove_watchdog() {
    [ -f "$WATCHDOG_FILE" ] && sed -i '/sing-box/d' "$WATCHDOG_FILE" 2>/dev/null
}

start() {
    if [ -f "$HOT_RELOADED_MARKER" ]; then
        rm -f "$HOT_RELOADED_MARKER"
        return 0
    fi

    if [ "$(nv singbox_enable)" != "1" ]; then
        stop
        return 0
    fi

    if [ "$(nv tailscale_enable)" = "1" ] || [ -n "$(pidof tailscaled)" ]; then
        log "CẢNH BÁO: Tailscale native đang bật -> DỪNG sing-box"
        stop purge
        return 1
    fi

    if is_running; then
        return 0
    fi

    log "Starting sing-box..."
    rotate_log
    mkdir -p "$WORK_DIR"
    fix_resolv_conf

    ensure_binary || return 1
    ensure_dashboard
    ensure_config
    mode_now="$(nv singbox_mode)"

    mem_limit="$(nv singbox_mem_limit)"
    [ -z "$mem_limit" ] && mem_limit="192MiB"
    export GOMEMLIMIT="$mem_limit"
    export GOGC=80

    cd "$WORK_DIR" && "$BIN_PATH" run -c "$CFG_PATH" >> "$LOG_FILE" 2>&1 &
    sleep 2

    if ! is_running; then
        log "LỖI: Sing-box không khởi động được"
        return 1
    fi
    log "Process started (PID $(pidof sing-box))"

    apply_iptables_mode
    install_watchdog
    install_post_iptables_hook
    sync_cron_state

    echo "${mode_now}:${mem_limit}" > "$LAST_MODE_FILE" 2>/dev/null
    return 0
}

stop() {
    sb_enable_now="$(nv singbox_enable)"

    # Xử lý Hot-Reload nếu chỉ thay đổi config nhẹ trên WebUI
    if [ "$1" != "purge" ] && [ "$sb_enable_now" = "1" ] && is_running; then
        new_mode="$(nv singbox_mode)"
        new_mem="$(nv singbox_mem_limit)"
        [ -z "$new_mem" ] && new_mem="192MiB"
        last_state="$(cat "$LAST_MODE_FILE" 2>/dev/null)"

        if [ "$last_state" = "${new_mode}:${new_mem}" ] && { [ "$new_mode" = "0" ] || [ "$new_mode" = "1" ]; }; then
            generate_config "$new_mode"
            if hot_reload_config; then
                apply_iptables_mode
                touch "$HOT_RELOADED_MARKER"
                return 0
            fi
        fi
    fi

    log "Stopping sing-box..."
    remove_watchdog
    remove_cron
    clean_iptables

    killall sing-box 2>/dev/null
    tries=0
    while is_running && [ $tries -lt 4 ]; do
        sleep 1
        tries=$((tries + 1))
    done
    is_running && killall -9 sing-box 2>/dev/null

    if [ "$1" = "purge" ] || [ "$sb_enable_now" != "1" ]; then
        rm -rf /tmp/sing-box "$LOG_FILE"
    fi
    log "Stopped"
}

hot_reload_config() {
    command -v curl >/dev/null 2>&1 || return 1
    http_code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
        --max-time 5 -H 'Content-Type: application/json' \
        -d "{\"path\":\"${CFG_PATH}\"}" \
        "http://127.0.0.1:9090/configs?force=true" 2>/dev/null)"
    [ "$http_code" = "204" ] || [ "$http_code" = "200" ]
}

restart() {
    stop
    sleep 1
    start
}

status() {
    is_running && echo "running" || echo "stopped"
}

check_ts_conflict() {
    if is_running && { [ "$(nv tailscale_enable)" = "1" ] || [ -n "$(pidof tailscaled)" ]; }; then
        log "Phát hiện Tailscale native -> Dừng sing-box"
        stop purge
    fi
}

case "$1" in
    start)      start ;;
    stop)       stop "$2" ;;
    restart)    restart ;;
    status)     status ;;
    update_sub) rotate_log; update_sub "$2" ;;
    fix_resolv_conf) fix_resolv_conf ;;
    check_ts_conflict) check_ts_conflict ;;
    reapply_iptables)
        is_running && apply_iptables_mode
        ;;
    *) echo "Usage: $0 {start|stop|restart|status|update_sub|reapply_iptables}" ;;
esac
