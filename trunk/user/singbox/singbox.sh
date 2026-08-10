#!/bin/sh
# sing-box lifecycle manager for Newifi 3 D2 (MT7621AT - IPSet TProxy & Tailscale & AGH Edition)
# Quản lý vòng đời Sing-box - Định tuyến IPTables do /etc/storage/singbox_route.sh đảm nhận

export PATH="/opt/sbin:/opt/bin:$PATH"

BIN_DIR="/tmp/sing-box"
BIN_PATH="$BIN_DIR/sing-box"
CFG_PATH="/etc/storage/singbox.conf"
CFG_MARKER="/tmp/sing-box/singbox.conf.autogen"
WORK_DIR="/tmp/sing-box/work"
LOG_FILE="/tmp/singbox.log"
LOG_TAG="sing-box"
WATCHDOG_FILE="/tmp/script/_opt_script_check"
FORCE_FETCH_MARKER="/tmp/sing-box/.force_fetch"
ROUTE_SCRIPT="/etc_ro/singbox/singbox_route.sh"

LAST_SUB_UPDATE_FILE="/etc/storage/singbox_last_sub_update"
SUB_UPDATE_INTERVAL=259200
CRON_TAG="singbox_autoupdate"

# Đường dẫn file Cron trực tiếp của Padavan
CRON_FILE="/etc/storage/cron/crontabs/$(nvram get http_username 2>/dev/null)"
[ -z "$CRON_FILE" ] || [ ! -f "$CRON_FILE" ] && CRON_FILE="/etc/storage/cron/crontabs/admin"

# Cấu hình Repo và tên Asset
REPO="shtorm-7/sing-box-extended"
GH_API="https://api.github.com/repos/${REPO}/releases/latest"

# Sử dụng trực tiếp jq đã tích hợp trong Firmware
JQ_BIN="/usr/bin/jq"

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof sing-box)" ]
}

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

ASSET_NAME="linux-mipsle-softfloat"

download_binary() {
    log "Đang tải sing-box từ ${REPO} về RAM (/tmp/sing-box)..."
    mkdir -p "$BIN_DIR"

    dl_url="$(curl -sk --connect-timeout 4 "$GH_API" 2>/dev/null \
        | grep -E "browser_download_url.*${ASSET_NAME}\.tar\.gz" \
        | cut -d'"' -f4 | head -n1)"

    if [ -z "$dl_url" ]; then
        log "Không tìm thấy asset ${ASSET_NAME} trong Release của ${REPO}"
        return 1
    fi

    tmp_file="/tmp/sing-box/download_sb.tmp"
    curl -Lksfo "$tmp_file" --connect-timeout 5 --retry 2 --max-time 90 "$dl_url" \
        || wget --no-check-certificate -T 15 -t 2 -q -O "$tmp_file" "$dl_url"

    size="$(wc -c < "$tmp_file" 2>/dev/null)"
    if [ -z "$size" ] || [ "$size" -lt 100000 ]; then
        log "Tải sing-box thất bại hoặc file quá nhỏ (size=${size:-0} bytes)"
        rm -f "$tmp_file"
        return 1
    fi

    case "$dl_url" in
        *.tar.gz|*.tgz)
            tar -xzf "$tmp_file" -C "$BIN_DIR/" 2>/dev/null
            rm -f "$tmp_file"
            extracted="$(find "$BIN_DIR" -type f -name "sing-box*" ! -name "*.tmp" | head -n1)"
            [ -n "$extracted" ] && mv -f "$extracted" "$BIN_PATH"
            ;;
        *.zip)
            unzip -q -o "$tmp_file" -d "$BIN_DIR/" 2>/dev/null
            rm -f "$tmp_file"
            extracted="$(find "$BIN_DIR" -type f -name "sing-box*" ! -name "*.tmp" | head -n1)"
            [ -n "$extracted" ] && mv -f "$extracted" "$BIN_PATH"
            ;;
        *)
            mv -f "$tmp_file" "$BIN_PATH"
            ;;
    esac

    chmod +x "$BIN_PATH"
    if ! "$BIN_PATH" version >/dev/null 2>&1 ; then
        log "Binary sing-box sau khi xả nén bị lỗi!"
        rm -f "$BIN_PATH"
        return 1
    fi

    log "sing-box đã sẵn sàng trên RAM: $BIN_PATH"
    return 0
}

ensure_binary() {
    for p in /usr/bin/sing-box /usr/sbin/sing-box /opt/bin/sing-box; do
        if [ -x "$p" ] && "$p" version >/dev/null 2>&1; then
            BIN_PATH="$p"
            return 0
        fi
    done

    BIN_PATH="/tmp/sing-box/sing-box"
    if [ -f "$BIN_PATH" ]; then
        chmod +x "$BIN_PATH"
        if "$BIN_PATH" version >/dev/null 2>&1; then
            return 0
        fi
    fi

    rm -f "$BIN_PATH"
    download_binary
}

UI_DIR="/tmp/sing-box/ui"
UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"

ensure_dashboard() {
    if [ -f "/etc/storage/singbox_ui.tar.gz" ]; then
        log "Cleaning up old UI archive from /etc/storage..."
        rm -f "/etc/storage/singbox_ui.tar.gz"
    fi

    [ -f "$UI_DIR/index.html" ] && return 0

    log "Downloading Clash-compatible dashboard (metacubexd)..."
    mkdir -p "$UI_DIR"
    tmp_zip="/tmp/sing-box/ui.zip"

    curl -Lksfo "$tmp_zip" --connect-timeout 5 --retry 2 --max-time 60 "$UI_URL" \
        || wget --no-check-certificate -T 15 -t 2 -q -O "$tmp_zip" "$UI_URL"

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

have_jq() {
    [ -x "$JQ_BIN" ] && return 0
    return 1
}

ensure_converter() {
    CONVERTER_PATH="/tmp/sing-box/converter.lua"
    if [ ! -f "$CONVERTER_PATH" ]; then
        if [ -f "/etc_ro/singbox/converter.lua" ]; then
            cp -f "/etc_ro/singbox/converter.lua" "$CONVERTER_PATH"
        else
            log "Tải converter.lua về RAM từ GitHub..."
            curl -Lksfo "$CONVERTER_PATH" --connect-timeout 5 "https://raw.githubusercontent.com/Sophiedevops/singbox-padavan-easy-crawler-2/main/converter.lua"
        fi
    fi
}

build_dns_block() {
    dns_final_detour="$1"
    dns_mode="$2"
    [ -z "$dns_final_detour" ] && dns_final_detour="direct"
    [ -z "$dns_mode" ] && dns_mode="1"

    case "$dns_mode" in
    0)
        cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" }
    ],
    "final": "dns-direct",
    "independent_cache": true
  },
EOF
        ;;
    2)
        cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-doh", "type": "https", "server": "1.1.1.1", "detour": "direct" }
    ],
    "final": "dns-doh",
    "independent_cache": true
  },
EOF
        ;;
    *)
        cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-remote", "type": "tls", "server": "8.8.8.8", "detour": "${dns_final_detour}" },
      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" },
      { "tag": "dns-fakeip", "type": "fakeip", "inet4_range": "198.18.0.0/15" }
    ],
    "rules": [
      { "domain_suffix": ["githubusercontent.com", "github.com", "adguard.com", "adguard-dns.com"], "server": "dns-direct" },
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
    bypass_vn="$1"; adblock="$2"; final_tag="$3"; rt_mode="$4"; dns_mode="$5"; ts_enable="$6"
    rulesets=""
    rules=""

    ts_route_rule=""
    if [ "$ts_enable" = "1" ]; then
        ts_route_rule='      { "ip_cidr": ["100.64.0.0/10"], "outbound": "ts-ep" },
'
    fi

    case "$dns_mode" in
    2) default_resolver_tag="dns-doh" ;;
    *) default_resolver_tag="dns-direct" ;;
    esac

    if [ "$rt_mode" = "0" ]; then
        sniff_rule='      { "inbound": "mixed-in", "action": "sniff" },
'
    else
        sniff_rule='      { "inbound": "tproxy-in", "action": "sniff" },
      { "inbound": "dns-in", "action": "sniff" },
'
    fi

    resolve_rule=""
    if [ "$bypass_vn" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geoip-vn\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://testingcf.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-vn.srs\", \"download_detour\": \"direct\" },
"
        rules="${rules}    { \"rule_set\": \"geoip-vn\", \"outbound\": \"direct\" },
"
        if [ "$dns_mode" = "1" ]; then
            resolve_rule='      { "action": "resolve", "server": "dns-remote" },
'
        else
            resolve_rule='      { "action": "resolve" },
'
        fi
    fi

    if [ "$adblock" = "1" ]; then
        rulesets="${rulesets}    { \"tag\": \"geosite-ads\", \"type\": \"remote\", \"format\": \"binary\", \"url\": \"https://testingcf.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-category-ads-all.srs\", \"download_detour\": \"direct\" },
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
${sniff_rule}      { "protocol": "dns", "action": "hijack-dns" },
${ts_route_rule}${resolve_rule}${rules}      { "ip_is_private": true, "outbound": "direct" }
    ],
    "final": "${final_tag}",
    "auto_detect_interface": true,
    "default_interface": "${WAN_IFACE}",
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
	
    [ -z "$sub_list_json" ] && { log "Chưa cấu hình Subscription nào trong danh sách"; return 1; }

    if ! have_jq; then
        log "LỖI CRITICAL: không tìm thấy 'jq' tại /usr/bin/jq."
        return 1;
    fi

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
            log "Danh sách Subscription không đổi -> dùng lại $cached_total nhóm đã tải trước (bỏ qua tải lại mạng)"
            return 0
        fi
    fi

    count="$(echo "$sub_list_json" | "$JQ_BIN" 'length' 2>/dev/null)"
    case "$count" in ''|*[!0-9]*) log "Danh sách Subscription không đúng định dạng JSON"; return 1 ;; esac
    [ "$count" -gt 0 ] || { log "Danh sách Subscription rỗng"; return 1; }

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

        if [ "$enabled" = "false" ] || [ "$enabled" = "0" ]; then
            log "Bỏ qua Sub '$name' vì đang bị TẮT công tắc"
            continue
        fi

        [ -z "$name" ] && name="Group $i"
        [ -z "$url" ] && { log "Bỏ qua Sub #$i vì thiếu URL"; continue; }

        cache="$GROUP_DIR/sub_${i}.json"
        log "Đang tải sub '$name': $url"
        
        curl -Lksfo "$cache" --connect-timeout 4 --max-time 12 "$url" \
            || wget --no-check-certificate -T 10 -q -O "$cache" "$url"

        if ! "$JQ_BIN" -e '.outbounds' "$cache" >/dev/null 2>&1; then
            log "Sub '$name' không phải JSON chuẩn -> Giải mã link thô bằng converter.lua..."
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

        if ! "$JQ_BIN" -e '.outbounds' "$cache" >/dev/null 2>&1; then
            log "Sub '$name' sau giải mã vẫn không hợp lệ -> bỏ qua"
            continue
        fi

        proxies="$("$JQ_BIN" -c --arg pfx "${name} - " '
            [ .outbounds[]
              | select(.type!="direct" and .type!="block" and .type!="dns" and .type!="selector" and .type!="urltest")
              | .tag = ($pfx + .tag) ][0:300]' "$cache" 2>/dev/null)"
        [ -z "$proxies" ] && proxies="[]"

        pcount="$(echo "$proxies" | "$JQ_BIN" 'length' 2>/dev/null)"
        case "$pcount" in ''|*[!0-9]*) pcount=0 ;; esac
        if [ "$pcount" -le 0 ]; then
            log "Sub '$name' không tìm thấy node proxy hợp lệ nào -> bỏ qua"
            continue
        fi

        echo "$proxies" | "$JQ_BIN" -c '.[]' >> "$GROUP_DIR/all_proxies.jsonl"

        group_outs="$(echo "$proxies" | "$JQ_BIN" -c '[.[].tag]')"
        "$JQ_BIN" -nc --arg tag "$name" --argjson outs "$group_outs" \
            '{type:"urltest", tag:$tag, outbounds:$outs, url:"http://www.gstatic.com/generate_204", interval:"5m", tolerance:50}' >> "$GROUP_DIR/all_selectors.jsonl"

        "$JQ_BIN" -c --arg t "$name" '. + [$t]' "$GROUP_DIR/group_tags.json" > "$GROUP_DIR/group_tags.json.tmp" \
            && mv "$GROUP_DIR/group_tags.json.tmp" "$GROUP_DIR/group_tags.json"
    done

    total_groups="$("$JQ_BIN" 'length' "$GROUP_DIR/group_tags.json" 2>/dev/null)"
    case "$total_groups" in ''|*[!0-9]*) total_groups=0 ;; esac

    if [ "$total_groups" -gt 0 ] && [ -n "$sub_hash" ]; then
        echo "$sub_hash" > "$GROUP_DIR/.sub_hash"
    fi

    [ "$total_groups" -gt 0 ]
}

build_endpoints_block() {
    ts_enable="$1"
    if [ "$ts_enable" != "1" ]; then
        return 0
    fi

    if ! have_jq; then
        log "LỖI: không tìm thấy jq, không thể build Tailscale endpoint an toàn -> bỏ qua endpoints"
        return 0
    fi

    ts_authkey="$(nv singbox_ts_authkey)"
    ts_hostname="$(nv singbox_ts_hostname)"
    ts_control_url="$(nv singbox_ts_control_url)"
    ts_exit_node="$(nv singbox_ts_exit_node)"

    ts_accept_routes="$(nv singbox_ts_accept_routes)";        [ "$ts_accept_routes" = "1" ] && ts_ar=true || ts_ar=false
    ts_ephemeral="$(nv singbox_ts_ephemeral)";                [ "$ts_ephemeral" = "1" ] && ts_eph=true || ts_eph=false
    ts_exit_lan="$(nv singbox_ts_exit_node_allow_lan)";       [ "$ts_exit_lan" = "1" ] && ts_exl=true || ts_exl=false
    ts_adv_exit="$(nv singbox_ts_advertise_exit_node)";       [ "$ts_adv_exit" = "1" ] && ts_advexit=true || ts_advexit=false
    ts_ssh="$(nv singbox_ts_ssh_server)";                     [ "$ts_ssh" = "1" ] && ts_sshv=true || ts_sshv=false

    sb_ver="$("$BIN_PATH" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    if [ -n "$sb_ver" ]; then
        highest="$(printf '%s\n%s\n' "1.14.0" "$sb_ver" | sort -V | tail -n1)"
        [ "$highest" = "$sb_ver" ] && ts_ssh_supported=true || ts_ssh_supported=false
    else
        ts_ssh_supported=false
    fi

    adv_routes_json="$(echo "$(nv singbox_ts_advertise_routes)" | "$JQ_BIN" -R -c \
        'split(",") | map(gsub("^[ \t]+|[ \t]+$";"")) | map(select(length>0))' 2>/dev/null)"
    [ -z "$adv_routes_json" ] && adv_routes_json="[]"

    adv_tags_json="$(echo "$(nv singbox_ts_advertise_tags)" | "$JQ_BIN" -R -c \
        'split(",") | map(gsub("^[ \t]+|[ \t]+$";"")) | map(select(length>0))' 2>/dev/null)"
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

    if [ -z "$ts_endpoint_json" ]; then
        log "LỖI: jq build Tailscale endpoint JSON thất bại -> bỏ qua endpoints"
        return 0
    fi

    echo "  \"endpoints\": [ ${ts_endpoint_json} ],"
}

get_wan_iface() {
    iface="$(nv wan_ifname)"
    if [ -z "$iface" ]; then
        iface="$(ip route show default 2>/dev/null | grep -v tailscale0 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)"
    fi
    [ -z "$iface" ] && iface="eth2.2"
    echo "$iface"
}

generate_config() {
    mode="$1"
    WAN_IFACE="$(get_wan_iface)"

    ts_enable="$(nv singbox_ts_enable)"
    [ -z "$ts_enable" ] && ts_enable="0"
    
    mem_limit="$(nv singbox_mem_limit)"
    [ -z "$mem_limit" ] && mem_limit="192MiB"
    
    bypass_vn="$(nv singbox_bypass_vn)"
    [ -z "$bypass_vn" ] && bypass_vn="0"
    
    adblock="$(nv singbox_adblock)"
    [ -z "$adblock" ] && adblock="0"
    
    dns_mode="$(nv singbox_dns_mode)"
    [ -z "$dns_mode" ] && dns_mode="1"

    if [ "$mode" = "0" ] && [ "$dns_mode" = "1" ]; then
        log "Mixed mode không hỗ trợ FakeIP -> chuyển dns_mode về Direct"
        dns_mode="0"
    fi

    if [ "$mode" = "0" ]; then
        inbound_block='  "inbounds": [ { "type": "mixed", "tag": "mixed-in", "listen": "0.0.0.0", "listen_port": 7890 } ],'
    else
        inbound_block='  "inbounds": [ 
          { "type": "tproxy", "tag": "tproxy-in", "listen": "0.0.0.0", "listen_port": 7893 },
          { "type": "direct", "tag": "dns-in", "listen": "0.0.0.0", "listen_port": 5353 }
        ],'
    fi

    if fetch_all_groups; then
        final_tag="select"
        master_outs="$("$JQ_BIN" -c '. + ["direct"]' "$GROUP_DIR/group_tags.json")"
        selector_block=$("$JQ_BIN" -nc --argjson outs "$master_outs" '{type:"selector", tag:"select", outbounds:$outs}')
        selector_block="    ${selector_block},"
        group_selectors_body="$(sed 's/$/,/' "$GROUP_DIR/all_selectors.jsonl")"
        outbounds_body="$(sed 's/$/,/' "$GROUP_DIR/all_proxies.jsonl")"
        
        total_g="$("$JQ_BIN" 'length' "$GROUP_DIR/group_tags.json" 2>/dev/null)"
        log "Đã nạp thành công $total_g nhóm Proxy từ Subscription."
    else
        log "CẢNH BÁO: Chưa có Subscription -> Chuyển sang chế độ kết nối Trực tiếp (Direct)."
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
        build_dns_block "$final_tag" "$dns_mode"
        build_route_block "$bypass_vn" "$adblock" "$final_tag" "$mode" "$dns_mode" "$ts_enable"
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

    log "Đã sinh config.json TProxy (mode=$mode, mem_limit=$mem_limit, bypass_vn=$bypass_vn, adblock=$adblock, dns_mode=$dns_mode, final=$final_tag)"
}

# --- UỶ QUYỀN ĐỊNH TUYẾN SANG /etc/storage/singbox_route.sh ---
apply_iptables_mode() {
    sb_mode="$(nv singbox_mode)"
    if [ "$sb_mode" = "1" ]; then
        if [ -x "$ROUTE_SCRIPT" ]; then
            log "Gọi script định tuyến chuyên dụng ($ROUTE_SCRIPT start)..."
            if ! "$ROUTE_SCRIPT" start; then
                log "LỖI: $ROUTE_SCRIPT start thất bại (xem log 'singbox-route' để biết chi tiết) - TProxy có thể KHÔNG hoạt động"
                return 1
            fi
        else
            log "LỖI CRITICAL: Không tìm thấy file $ROUTE_SCRIPT hoặc chưa được cấp quyền chmod +x"
            return 1
        fi
    else
        clean_iptables
    fi
    return 0
}

clean_iptables() {
    if [ -x "$ROUTE_SCRIPT" ]; then
        log "Gọi gỡ bỏ định tuyến ($ROUTE_SCRIPT stop)..."
        "$ROUTE_SCRIPT" stop
    fi
}

install_cron() {
    cron_cmd="0 4 * * * /usr/bin/singbox.sh update_sub #$CRON_TAG"
    
    mkdir -p "$(dirname "$CRON_FILE")" 2>/dev/null
    touch "$CRON_FILE" 2>/dev/null
    
    sed -i "/$CRON_TAG/d" "$CRON_FILE" 2>/dev/null
    echo "$cron_cmd" >> "$CRON_FILE"
    
    killall -HUP crond 2>/dev/null
    log "Đã bật lịch tự động cập nhật Sub (04:00 mỗi ngày)"
    return 0
}

remove_cron() {
    if [ -f "$CRON_FILE" ]; then
        sed -i "/$CRON_TAG/d" "$CRON_FILE" 2>/dev/null
        killall -HUP crond 2>/dev/null
    fi
    log "Đã tắt lịch tự động cập nhật Sub"
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
            log "update_sub: lần cập nhật gần nhất cách đây $((elapsed / 3600))h -> bỏ qua"
            return 0
        fi
    fi

    sb_mode="$(nv singbox_mode)"
    case "$sb_mode" in
        0|1) ;;
        *)
            log "update_sub: Mode 3 dùng Custom JSON nên bỏ qua"
            return 1
            ;;
    esac

    log "===== Cập nhật Subscription ====="

    mkdir -p "$(dirname "$FORCE_FETCH_MARKER")" 2>/dev/null
    touch "$FORCE_FETCH_MARKER"

    if is_running; then
        restart
        ok=$?
    else
        generate_config "$sb_mode"
        ok=0
    fi

    if [ "$ok" = "0" ]; then
        echo "$now" > "$LAST_SUB_UPDATE_FILE"
        log "===== Cập nhật Subscription hoàn tất ====="
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
                log "CẢNH BÁO: Mode 3 rỗng."
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
            fi
            ;;
    esac
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
    if [ "$(nv singbox_enable)" != "1" ]; then
        log "singbox_enable=0 -> stop & purge RAM"
        stop purge
        return 0
    fi

    if [ "$(nv tailscale_enable)" = "1" ] || [ -n "$(pidof tailscaled)" ]; then
        log "CẢNH BÁO: Tailscale native đang bật -> CHẶN sing-box để tránh xung đột"
        stop purge
        return 1
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
    [ -z "$mem_limit" ] && mem_limit="192MiB"
    export GOMEMLIMIT="$mem_limit"
    export GOGC=80

    cd "$WORK_DIR" && "$BIN_PATH" run -c "$CFG_PATH" >> "$LOG_FILE" 2>&1 &

    sleep 2
    if ! is_running; then
        log "Process exited immediately after start"
        return 1
    fi
    log "Process started (PID $(pidof sing-box))"

    apply_iptables_mode
    install_watchdog
    sync_cron_state
    return 0
}

stop() {
    purge="$1"

    log "Stopping..."
    remove_watchdog
    remove_cron
    clean_iptables

    killall sing-box 2>/dev/null

    tries=0
    while is_running && [ $tries -lt 5 ]; do
        sleep 1
        tries=$((tries + 1))
    done

    if is_running; then
        killall -9 sing-box 2>/dev/null
    fi

    if [ "$purge" = "purge" ]; then
        log "Đọn dẹp RAM tmpfs /tmp/sing-box..."
        rm -rf /tmp/sing-box
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

check_ts_conflict() {
    if is_running && { [ "$(nv tailscale_enable)" = "1" ] || [ -n "$(pidof tailscaled)" ]; }; then
        log "Phát hiện Tailscale native bật -> DỪNG sing-box"
        stop
    fi
}

case "$1" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    status)     status ;;
    update_sub) rotate_log; update_sub "$2" ;;
    check_ts_conflict) check_ts_conflict ;;
    reapply_iptables)
        is_running && apply_iptables_mode
        ;;
    *) echo "Usage: $0 {start|stop|restart|status|update_sub [force]|reapply_iptables|check_ts_conflict}" ;;
esac
