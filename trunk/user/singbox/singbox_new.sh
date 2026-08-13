#!/bin/sh
# sing-box lifecycle manager for Newifi 3 D2 (MT7621AT - IPSet TProxy & Tailscale & AGH Edition)
# Quản lý vòng đời Sing-box - Định tuyến IPTables do /etc/storage/singbox_route.sh đảm nhận

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
            # Don sach thu muc cha vua giai nen (VD "sing-box-1.13.18-extended-
            # 2.6.4-linux-mipsle-softfloat/") - GitHub release tarball luon
            # boc file trong 1 thu muc cung ten ban release. Neu khong xoa,
            # moi lan auto_update tai ban moi se de lai THEM 1 thu muc rac
            # moi (ten khac do so ban khac) - ro ri RAM cong don qua thoi gian.
            find "$BIN_DIR" -mindepth 1 -maxdepth 1 -type d -name "sing-box-*" -exec rm -rf {} + 2>/dev/null
            ;;
        *.zip)
            unzip -q -o "$tmp_file" -d "$BIN_DIR/" 2>/dev/null
            rm -f "$tmp_file"
            extracted="$(find "$BIN_DIR" -type f -name "sing-box*" ! -name "*.tmp" | head -n1)"
            [ -n "$extracted" ] && mv -f "$extracted" "$BIN_PATH"
            find "$BIN_DIR" -mindepth 1 -maxdepth 1 -type d -name "sing-box-*" -exec rm -rf {} + 2>/dev/null
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
    agh_dns_bypass="$3"
    [ -z "$dns_final_detour" ] && dns_final_detour="direct"
    [ -z "$dns_mode" ] && dns_mode="1"
    [ -z "$agh_dns_bypass" ] && agh_dns_bypass="0"

    # dns-in-agh (127.0.0.1:5354) la inbound RIENG, CHI danh cho AGH tu ket
    # noi vao (khong phai LAN client) - de AGH luon nhan IP THAT (khong bao
    # gio dinh fakeip du dang o mode FakeIP), VA van duoc tunnel qua proxy
    # dang chon khi co the (mode FakeIP dung dns-remote co detour:select).
    # CHI dua rule nay vao khi cong tac singbox_agh_dns_bypass=1 (nguoi
    # dung tu bat tren WebUI) - khi bat, ap dung DONG LOAT ca 3 dns_mode
    # (khong chi rieng FakeIP) de AGH luon dung 1 cong co dinh, khong phai
    # doi tay moi lan doi qua lai dns_mode.
    agh_rule=""
    agh_rule_only=""
    if [ "$agh_dns_bypass" = "1" ]; then
        case "$dns_mode" in
        0)
            agh_rule_only='      { "inbound": "dns-in-agh", "server": "dns-direct" }
'
            ;;
        2)
            agh_rule_only='      { "inbound": "dns-in-agh", "server": "dns-doh" }
'
            ;;
        *)
            agh_rule='      { "inbound": "dns-in-agh", "server": "dns-remote" },
'
            ;;
        esac
    fi

    case "$dns_mode" in
    0)
        cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
${agh_rule_only}    ],
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
    "rules": [
${agh_rule_only}    ],
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
${agh_rule}      { "domain_suffix": ["githubusercontent.com", "github.com", "adguard.com", "adguard-dns.com"], "server": "dns-direct" },
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
        # Ca IPv4 CGNAT (100.64.0.0/10) VA IPv6 ULA (fd7a:115c:a1e0::/48 -
        # day la prefix ULA mac dinh Tailscale cap cho moi node, thay tren
        # log thuc te truoc day: "nameserver fd7a:115c:a1e0::53") deu phai
        # route vao ts-ep. Neu thieu IPv6, ket noi toi peer qua dia chi ULA
        # (thay vi IPv4 100.x.x.x) se roi xuong "ip_is_private -> direct"
        # va fail vi khong co interface kernel nao so huu dai do.
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
        sniff_rule="      { \"inbound\": \"tproxy-in\", \"action\": \"sniff\" },
      { \"inbound\": \"dns-in\", \"action\": \"sniff\" },
${agh_sniff}"
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

    # Chuan hoa JSON qua jq -c TRUOC khi hash - nvram/apply.cgi co the lam
    # lech whitespace/format cua chuoi (VD textarea HTML round-trip) moi lan
    # Apply BAT KY setting nao, du noi dung logic (danh sach sub) khong doi.
    # Neu hash tinh tren chuoi tho chua chuan hoa, sai lech whitespace do se
    # lam sub_hash khac di MOI LAN APPLY, kich hoat "rm -rf GROUP_DIR" +
    # tai lai toan bo subscription tu mang mot cach khong can thiet.
    sub_list_json="$(echo "$sub_list_json" | "$JQ_BIN" -c '.' 2>/dev/null)"
    [ -z "$sub_list_json" ] && { log "Danh sách Subscription không phải JSON hợp lệ"; return 1; }

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

    # Cong tac thu cong "DNS Thuc Noi Bo" (Real DNS): bat "dns-in-agh" (cong
    # dinh FakeIP + van duoc tunnel qua proxy khi co the) o CA 3 dns_mode
    # (Direct/FakeIP/DoH) khi bat, khong phan biet - dung theo yeu cau: bat
    # la ap dung dong loat, tranh nguoi dung phai nho doi cong AGH moi lan
    # doi qua lai dns_mode.
    agh_dns_bypass="$(nv singbox_agh_dns_bypass)"
    [ -z "$agh_dns_bypass" ] && agh_dns_bypass="0"

    if [ "$mode" = "0" ] && [ "$dns_mode" = "1" ]; then
        log "Mixed mode không hỗ trợ FakeIP -> chuyển dns_mode về Direct"
        dns_mode="0"
    fi

    agh_dns_in=""
    if [ "$agh_dns_bypass" = "1" ]; then
        agh_dns_in=',
          { "type": "direct", "tag": "dns-in-agh", "listen": "127.0.0.1", "listen_port": 5354 }'
    fi

    if [ "$mode" = "0" ]; then
        inbound_block="  \"inbounds\": [
          { \"type\": \"mixed\", \"tag\": \"mixed-in\", \"listen\": \"0.0.0.0\", \"listen_port\": 7890 }${agh_dns_in}
        ],"
    else
        inbound_block="  \"inbounds\": [ 
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
        build_dns_block "$final_tag" "$dns_mode" "$agh_dns_bypass"
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

fix_resolv_conf() {
    # Go "nameserver 127.0.0.1" khoi resolv.conf cua chinh router (neu co).
    # Ly do: cac tien trinh chay ngay tren router (AGH tu update filter,
    # curl/wget tai sub/geoip/binary ben duoi) se hoi DNS qua 127.0.0.1 -> AGH
    # -> upstream 127.0.0.1:5353 (sing-box) -> nhan ve fake-ip (198.18.x.x).
    # Nhung traffic tu than cua router KHONG di qua br0 nen khong duoc TPROXY
    # dich nguoc fake-ip -> domain that, ket noi toi fake-ip se luon timeout.
    # Router tu dung thang DNS that (tu ISP/nvram) la du, khong can fake-ip.
    #
    # CHI con goi o dau start() (truoc ensure_binary), KHONG con chay dinh ky
    # qua watchdog nua - vi singbox_route.sh (buoc 8, trong start_routing())
    # da tu dong don dong nay moi khi routing duoc ap dung lai (moi lan WAN
    # reconnect goi reapply_iptables), lam watchdog goi rieng bi thua. Nhung
    # KHONG the bo hoan toan: singbox_route.sh CHI chay duoc SAU KHI sing-box
    # da start thanh cong (start_routing() tu return 1 neu pidof sing-box
    # rong), trong khi ensure_binary/download_binary (tai binary qua GitHub
    # API) xay ra TRUOC do - neu luc do resolv.conf van ket 127.0.0.1 thi tai
    # binary se treo, khong co singbox_route.sh nao cuu duoc o buoc nay (bai
    # toan con-ga-qua-trung).
    if [ -f /etc/resolv.conf ] && grep -q "^nameserver 127.0.0.1$" /etc/resolv.conf; then
        sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.conf
        log "Da go nameserver 127.0.0.1 khoi /etc/resolv.conf de tranh router tu dinh fake-ip"
    fi
}

install_post_iptables_hook() {
    # File "Custom user script" cua Padavan (goi TU DONG sau moi lan ROM
    # rebuild iptables noi bo - WAN reconnect, Apply settings...). Day la
    # noi DUY NHAT co the bat sing-box tu apply lai chain SINGBOX sau su
    # kien do (xem case "reapply_iptables" cuoi file) - khong co dong nay,
    # chain SINGBOX se mat sau moi lan reconnect WAN du sing-box van song.
    #
    # File nay KHONG nam trong ROMFS (chi dong goi 1 lan luc build firmware)
    # ma nam tren phan vung ghi duoc /etc/storage, duoc tao lai moi lan
    # factory-reset/flash firmware moi - nen KHONG the "build san" qua
    # Makefile cua goi sing-box duoc. Thay vao do tu cai dat (idempotent)
    # moi lan start(), giong het cach lam voi WATCHDOG_FILE o tren - chi xoa
    # dung dong hook cu cua chinh minh, KHONG dung/ghi de noi dung khac
    # nguoi dung hoac goi khac da them vao file dung chung nay.
    post_ipt_file="/etc/storage/post_iptables_script.sh"
    if [ ! -f "$post_ipt_file" ]; then
        echo '#!/bin/sh' > "$post_ipt_file"
        chmod +x "$post_ipt_file"
    fi
    sed -i '/singbox\.sh reapply_iptables/d' "$post_ipt_file" 2>/dev/null
    cat >> "$post_ipt_file" <<-EOF

### sing-box: reapply TPROXY chain sau khi Padavan flush/rebuild iptables noi
### bo (WAN reconnect, Apply settings...). Neu khong co dong nay, chain
### SINGBOX se bi mat sau moi lan reconnect WAN, gay mat mang toan bo LAN
### du sing-box van dang chay binh thuong (bug da tung gap va debug ky).
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
    # QUAN TRONG: services.c goi "singbox.sh stop" roi "singbox.sh start"
    # nhu 2 tien trinh eval() RIENG BIET (khong bao gio goi "restart") - moi
    # lan Apply settings (singbox_enable van =1), C VAN goi stop_singbox()
    # truoc, sau do goi start_singbox() vi enable=1. Neu stop() vua roi da
    # hot-reload thanh cong (xem comment trong stop()), no de lai marker nay
    # de bao start() KHONG can khoi dong lai tu dau - process van dang chay
    # voi config moi roi.
    if [ -f "$HOT_RELOADED_MARKER" ]; then
        rm -f "$HOT_RELOADED_MARKER"
        log "Đã hot-reload thành công ở bước stop() trước đó -> bỏ qua start lại từ đầu"
        return 0
    fi

    if [ "$(nv singbox_enable)" != "1" ]; then
        log "singbox_enable=0 -> stop & purge RAM"
        stop
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

    fix_resolv_conf

    if ! ensure_binary; then
        log "Cannot start: no working binary"
        return 1
    fi

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
        log "Process exited immediately after start"
        return 1
    fi
    log "Process started (PID $(pidof sing-box))"

    apply_iptables_mode
    install_watchdog
    install_post_iptables_hook
    sync_cron_state

    # Ghi lai mode + mem_limit VUA ap dung thanh cong. restart() se so sanh
    # voi lan sau de quyet dinh: neu ca 2 khong doi -> co the hot-reload
    # (khong kill process); neu doi -> BAT BUOC full restart (mem_limit la
    # bien moi truong GOMEMLIMIT gan luc spawn process, khong the doi khi
    # dang chay; mode doi nghia la inbound/port/iptables khac han).
    echo "${mode_now}:${mem_limit}" > "$LAST_MODE_FILE" 2>/dev/null
    return 0
}

stop() {
    sb_enable_now="$(nvram get singbox_enable 2>/dev/null)"

    # QUAN TRONG: services.c dinh nghia restart_singbox() = stop_singbox()
    # + start_singbox() nhu 2 eval() TACH BIET (khong bao gio goi thang ham
    # restart() cua shell script nay - ham do chi chay duoc khi tu tay SSH
    # goi "singbox.sh restart"). Vi vay, de co che hot-reload qua Clash API
    # THAT SU co tac dung khi Apply qua WebUI, no PHAI nam trong chinh
    # stop() nay - thu hot-reload TRUOC KHI kill process, chi that su kill
    # neu hot-reload khong ap dung duoc/that bai.
    #
    # Dieu kien de thu hot-reload (khong purge, process dang song that):
    #   - Khong bi ep "purge" tuong minh
    #   - singbox_enable=1 LUC NAY -> day chi la buoc 1 cua chu ky Apply
    #     (start_singbox() se goi lai "start" NGAY SAU), KHONG PHAI tat han
    #   - Process dang chay that (is_running)
    #   - mode + mem_limit KHONG doi so voi lan start truoc (2 gia tri nay
    #     anh huong inbound/port hoac GOMEMLIMIT luc spawn, khong the doi
    #     "nong" duoc)
    #   - mode dang la 0/1 (config tu sinh, khong phai Custom JSON)
    if [ "$1" != "purge" ] && [ "$sb_enable_now" = "1" ] && is_running; then
        new_mode="$(nv singbox_mode)"
        new_mem="$(nv singbox_mem_limit)"
        [ -z "$new_mem" ] && new_mem="192MiB"
        last_state="$(cat "$LAST_MODE_FILE" 2>/dev/null)"

        if [ "$last_state" = "${new_mode}:${new_mem}" ] \
            && { [ "$new_mode" = "0" ] || [ "$new_mode" = "1" ]; }; then
            log "Apply settings + mode/mem_limit không đổi -> thử HOT-RELOAD qua Clash API TRƯỚC khi kill process..."
            generate_config "$new_mode"
            if hot_reload_config; then
                log "Hot-reload thành công! KHÔNG kill process, giữ nguyên kết nối đang chạy."
                # Van goi lai apply_iptables_mode: toggle nhu singbox_dns_redirect
                # chi anh huong iptables/route script rieng, khong nam trong
                # JSON config nen hot-reload API o tren khong dong toi duoc.
                apply_iptables_mode
                touch "$HOT_RELOADED_MARKER"
                log "Stopped (hot-reload, process vẫn sống)"
                return 0
            fi
            log "Hot-reload thất bại (Clash API không phản hồi) -> tiếp tục stop/kill bình thường"
        fi
    fi

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

    # Ca 2 truong hop deu goi dung 1 lenh "singbox.sh stop" GIONG HET NHAU tu
    # C - khong co tham so nao phan biet duoc o tang goi lenh, nen PHAI tu
    # doc nvram TAI DAY de biet dung la tat han hay chi la Apply (da handle
    # o nhanh hot-reload phia tren, nhanh nay la fallback khi hot-reload
    # khong ap dung duoc hoac that bai):
    #   - singbox_enable=1 -> van la Apply, chi la hot-reload fail -> KHONG
    #     purge, giu binary/UI/cache de start() lai nhanh, khong tai lai
    #     tu mang.
    #   - singbox_enable!=1 -> tat that -> PURGE that su.
    if [ "$1" = "purge" ] || [ "$sb_enable_now" != "1" ]; then
        log "singbox_enable=${sb_enable_now:-0} (tắt hẳn) -> dọn dẹp RAM tmpfs /tmp/sing-box..."
        rm -rf /tmp/sing-box
        # LOG_FILE nam NGOAI thu muc /tmp/sing-box (path la /tmp/singbox.log,
        # khac cap, thieu dau "-"), nen "rm -rf /tmp/sing-box" o tren KHONG
        # dong toi file nay. Purge nghia la don sach hoan toan RAM lien quan
        # sing-box nen can xoa rieng o day.
        rm -f "$LOG_FILE"
    fi

    log "Stopped"
}

hot_reload_config() {
    # PUT /configs?force=true voi body {"path": "$CFG_PATH"} - day la Clash
    # API chuan (sing-box tuong thich, da bat san qua "clash_api" trong
    # config) de sing-box tu doc lai TOAN BO file config tu dau, ap dung
    # outbounds/route.rules/dns/endpoints MOI - hoan toan KHONG kill process,
    # khong mat ket noi TCP/TPROXY dang chay, khong can re-bind socket.
    if ! command -v curl >/dev/null 2>&1; then
        log "Không có curl -> không thể hot-reload, fallback restart đầy đủ"
        return 1
    fi
    http_code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
        --max-time 5 \
        -H 'Content-Type: application/json' \
        -d "{\"path\":\"${CFG_PATH}\"}" \
        "http://127.0.0.1:9090/configs?force=true" 2>/dev/null)"
    [ "$http_code" = "204" ] || [ "$http_code" = "200" ]
}

restart() {
    new_mode="$(nv singbox_mode)"
    new_mem="$(nv singbox_mem_limit)"
    [ -z "$new_mem" ] && new_mem="192MiB"
    last_state="$(cat "$LAST_MODE_FILE" 2>/dev/null)"

    # Chi thu hot-reload khi DU CA 3 dieu kien:
    # 1. sing-box dang chay that (khong phai dang stopped)
    # 2. mode (Mixed/TProxy) VA mem_limit deu KHONG doi so voi lan start
    #    truoc - vi 2 gia tri nay anh huong inbound/port (mode) hoac bien
    #    moi truong GOMEMLIMIT luc spawn (mem_limit), khong the doi "nong".
    # 3. mode dang la 0 (Mixed) hoac 1 (TProxy) - tuc config duoc TU SINH
    #    boi generate_config(), khong phai Custom JSON (mode khac) do
    #    nguoi dung tu viet tay (khong the biet chac ho co doi port/inbound
    #    hay khong, an toan hon la full restart cho truong hop do).
    if is_running \
        && [ "$last_state" = "${new_mode}:${new_mem}" ] \
        && { [ "$new_mode" = "0" ] || [ "$new_mode" = "1" ]; }; then

        log "Mode+mem_limit không đổi & đang chạy -> thử HOT-RELOAD qua Clash API (không kill process)"
        generate_config "$new_mode"

        if hot_reload_config; then
            log "Hot-reload thành công! Bỏ qua stop/start, giữ nguyên kết nối đang chạy."
            # Van goi lai apply_iptables_mode: mot so toggle (VD
            # singbox_dns_redirect) chi anh huong iptables/route script rieng,
            # KHONG nam trong JSON config sing-box nen hot-reload API o tren
            # khong dong toi duoc - phai chay lai o day de khong bo sot.
            # Lenh nay idempotent (dung -C check / flush+tao lai) nen chay
            # lai khong gay gian doan gi them.
            apply_iptables_mode
            return 0
        fi

        log "Hot-reload thất bại (Clash API không phản hồi/lỗi) -> fallback về restart đầy đủ"
    fi

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
        stop purge
    fi
}

case "$1" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    status)     status ;;
    update_sub) rotate_log; update_sub "$2" ;;
    fix_resolv_conf) fix_resolv_conf ;;
    check_ts_conflict) check_ts_conflict ;;
    reapply_iptables)
        is_running && apply_iptables_mode
        ;;
    *) echo "Usage: $0 {start|stop[=purge RAM]|restart[=stop nhe, giu binary]|status|update_sub [force]|fix_resolv_conf|reapply_iptables|check_ts_conflict}" ;;
esac
