#!/bin/sh
# sing-box lifecycle manager for Newifi 3 D2 (MT7621AT - IPSet TProxy & Tailscale & AGH Edition)

export PATH="/opt/sbin:/opt/bin:$PATH"

BIN_DIR="/tmp/sing-box"
BIN_PATH="$BIN_DIR/sing-box"
CFG_PATH="/etc/storage/singbox.conf"
CFG_MARKER="/tmp/sing-box/singbox.conf.autogen"
WORK_DIR="/tmp/sing-box/work"
LOG_FILE="/tmp/singbox.log"
LOG_TAG="sing-box"
WATCHDOG_FILE="/tmp/script/_opt_script_check"
RULESET_DIR="/tmp/sing-box/rule-set"
SUB_CACHE="/tmp/sing-box/sub_raw.json"

LAST_SUB_UPDATE_FILE="/etc/storage/singbox_last_sub_update"
SUB_UPDATE_INTERVAL=259200
CRON_TAG="singbox_autoupdate"

# Đường dẫn file Cron trực tiếp của Padavan
CRON_FILE="/etc/storage/cron/crontabs/$(nvram get http_username 2>/dev/null)"
[ -z "$CRON_FILE" ] || [ ! -f "$CRON_FILE" ] && CRON_FILE="/etc/storage/cron/crontabs/admin"

# Cấu hình Repo và tên Asset
REPO="shtorm-7/sing-box-extended"
GH_API="https://api.github.com/repos/${REPO}/releases/latest"
ASSET_NAME="linux-mipsle-softfloat-compressed"

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

download_binary() {
    log "Đang tải sing-box từ ${REPO} về RAM (/tmp/sing-box)..."
    mkdir -p "$BIN_DIR"

    dl_url="$(curl -sk --connect-timeout 4 "$GH_API" 2>/dev/null \
        | grep -E "browser_download_url.*(${ASSET_NAME}|\.tar\.gz|\.zip)" \
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
        # Direct: KHONG fake-ip. Tra ve IP that qua UDP thuan (khong ma hoa).
        # He qua: route theo domain (bypass_vn/adblock geosite) mat do chinh
        # xac tuyet doi cua fake-ip, phai dua vao sniff SNI/HTTP-Host + geoip
        # theo IP that. Uu diem: khong con bug "missing fakeip record" hay
        # cac tien trinh tren router (AGH, curl) tu dinh bay fake-ip nua, vi
        # moi IP tra ve deu la IP that, dinh tuyen duoc binh thuong.
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
        # DoH: giong Direct (khong fake-ip, tra IP that) nhung query duoc ma
        # hoa qua HTTPS toi Cloudflare, ISP khong soi duoc domain dang tra.
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
        # FakeIP (mac dinh, dns_mode=1): giu nguyen logic da test on dinh.
        cat <<-EOF
  "dns": {
    "servers": [
      { "tag": "dns-remote", "type": "tls", "server": "8.8.8.8", "detour": "${dns_final_detour}" },
      { "tag": "dns-direct", "type": "udp", "server": "1.1.1.1", "detour": "direct" },
      { "tag": "dns-fakeip", "type": "fakeip", "inet4_range": "198.18.0.0/15" }
    ],
    "rules": [
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
    bypass_vn="$1"; adblock="$2"; final_tag="$3"; rt_mode="$4"
    rulesets=""
    rules=""

    # Sniff SNI/HTTP-Host de biet domain cho rule bypass_vn/adblock (dua vao
    # geosite/geoip theo domain). Can cho CA 2 mode, khong chi TProxy:
    #   - Mixed (mixed-in): hau het app/browser tu resolve DNS bang resolver
    #     he thong roi moi noi proxy bang IP that (khong gui domain qua SOCKS/
    #     HTTP CONNECT nhu nhieu nguoi tuong, tru khi app tu bat "remote DNS").
    #     Neu khong sniff, sing-box chi thay IP, khong co domain nao de khop
    #     rule geosite-ads/geoip-vn -> adblock/bypass_vn im lang vo hieu.
    #   - TProxy (tproxy-in/dns-in): tuong tu, can sniff de bu lai truong hop
    #     dns_mode=Direct/DoH (khong co fake-ip de biet truoc domain).
    # Sniff SNI van hoat dong duoc du chi co IP, vi no doc thang byte TLS
    # ClientHello cua chinh ket noi dang chay qua, khong phu thuoc viec
    # sing-box nhan duoc domain hay IP luc dau.
    if [ "$rt_mode" = "0" ]; then
        sniff_rule='      { "inbound": "mixed-in", "action": "sniff" },
'
    else
        sniff_rule='      { "inbound": "tproxy-in", "action": "sniff" },
      { "inbound": "dns-in", "action": "sniff" },
'
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

    cat <<-EOF
  "route": {
    "rule_set": [
${rulesets%,
}
    ],
    "rules": [
${sniff_rule}      { "protocol": "dns", "action": "hijack-dns" },
${rules}      { "ip_is_private": true, "outbound": "direct" }
    ],
    "final": "${final_tag}",
    "auto_detect_interface": true
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

        # urltest: tự động chọn node có độ trễ thấp nhất trong group, đo lại mỗi 5 phút.
        # KHÔNG gộp "direct" vào đây vì direct gần như luôn thắng về latency,
        # sẽ làm urltest luôn chọn direct thay vì proxy thật -> mất tác dụng.
        group_outs="$(echo "$proxies" | "$JQ_BIN" -c '[.[].tag]')"
        "$JQ_BIN" -nc --arg tag "$name" --argjson outs "$group_outs" \
            '{type:"urltest", tag:$tag, outbounds:$outs, url:"http://www.gstatic.com/generate_204", interval:"5m", tolerance:50}' >> "$GROUP_DIR/all_selectors.jsonl"

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
    [ -z "$mem_limit" ] && mem_limit="192MiB"
    
    bypass_vn="$(nv singbox_bypass_vn)"
    [ -z "$bypass_vn" ] && bypass_vn="0"
    
    adblock="$(nv singbox_adblock)"
    [ -z "$adblock" ] && adblock="0"
    
    dns_mode="$(nv singbox_dns_mode)"
    # Mac dinh fallback = FakeIP ("1"), KHONG phai "0" (Direct) nhu truoc.
    # Ly do: day la mode da duoc test on dinh, dropdown DNS Mode truoc gio
    # khong co tac dung thuc te nen nhieu nguoi chua tung luu lua chon nao ->
    # nvram rong. Neu fallback ve Direct, he thong dang chay FakeIP on dinh se
    # tu dung mat fake-ip ngay sau khi ap ban nay. Chi Direct/DoH khi nguoi
    # dung THUC SU bam chon va Luu tren webui.
    [ -z "$dns_mode" ] && dns_mode="1"

    # Rang buoc dns_mode theo tung Proxy Mode (khop voi lua chon that su hop
    # le tren webui):
    #   - Mixed (mode=0): CHI hop le Direct hoac DoH. Mixed chi mo mixed-in
    #     (khong co dns-in), nen FakeIP khong co inbound nao de nhan DNS that
    #     su hoat dung dung nghia - neu nvram con luu FakeIP tu luc truoc
    #     dang o TProxy, ep ve Direct de tranh cau hinh vo nghia.
    #   - TProxy (mode=1): ca 3 (Direct/FakeIP/DoH) deu hop le, giu nguyen.
    if [ "$mode" = "0" ] && [ "$dns_mode" = "1" ]; then
        log "Mixed mode khong ho tro FakeIP (khong co dns-in) -> tu dong chuyen dns_mode ve Direct"
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
        log "CẢNH BÁO: Chưa có Subscription hoặc không tìm thấy Node hợp lệ -> Chuyển sang chế độ kết nối Trực tiếp (Direct)."
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
        echo "    \"cache_file\": { \"enabled\": true, \"path\": \"/tmp/sing-box/cache.db\" }"
        echo "  },"
        echo "$inbound_block"
        build_dns_block "$final_tag" "$dns_mode"
        build_route_block "$bypass_vn" "$adblock" "$final_tag" "$mode"
        echo "  \"outbounds\": ["
        echo "$selector_block"
        echo "$group_selectors_body"
        echo "$outbounds_body"
        echo "    { \"type\": \"direct\", \"tag\": \"direct\" },"
        echo "    { \"type\": \"block\", \"tag\": \"block\" }"
        echo "  ]"
        echo "}"
    } > "$CFG_PATH"

    # Danh dau day la config TU DONG SINH (khong phai ban tu tay dan vao o
    # Mode 3), de ensure_config() phat hien va canh bao neu sau nay ban
    # chuyen sang Custom JSON ma chua thay the noi dung that su.
    mkdir -p "$(dirname "$CFG_MARKER")" 2>/dev/null
    touch "$CFG_MARKER"

    log "Đã sinh config.json TProxy (mode=$mode, mem_limit=$mem_limit, bypass_vn=$bypass_vn, adblock=$adblock, dns_mode=$dns_mode, final=$final_tag)"
}

apply_iptables_mode() {
    sb_mode="$(nv singbox_mode)"
    if [ "$sb_mode" = "1" ]; then
        log "Applying IPTables TPROXY rules (IPSet Hash Optimized)..."

        for mod in nf_tproxy_core xt_TPROXY xt_socket xt_mark; do
            modprobe $mod 2>/dev/null
        done
        if ! lsmod | grep -q "xt_TPROXY"; then
            log "LỖI: không nạp được module xt_TPROXY - TProxy sẽ KHÔNG hoạt động."
        fi

        while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
        ip rule add fwmark 1 table 100 2>/dev/null
        ip route add local default dev lo table 100 2>/dev/null

        ipset create singbox_bypass hash:net 2>/dev/null
        ipset flush singbox_bypass 2>/dev/null
        for cidr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
            ipset add singbox_bypass $cidr 2>/dev/null
        done

        iptables -t mangle -N SINGBOX 2>/dev/null
        iptables -t mangle -F SINGBOX 2>/dev/null
        
        iptables -t mangle -A SINGBOX -m set --match-set singbox_bypass dst -j RETURN
        
        iptables -t mangle -A SINGBOX -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
        iptables -t mangle -A SINGBOX -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
        
        # Xoa het jump-rule cu (neu co, VD do sing-box tung bi crash roi
        # watchdog tu restart ma khong qua stop()/clean_iptables) truoc khi
        # chen lai, tranh tich lap trung nhieu ban PREROUTING -> SINGBOX qua
        # cac lan restart.
        while iptables -t mangle -D PREROUTING -i br0 -j SINGBOX 2>/dev/null; do :; done
        iptables -t mangle -I PREROUTING -i br0 -j SINGBOX 2>/dev/null

        # --- 2. CÔNG TẮC BẬT/TẮT CHUYỂN HƯỚNG DNS (PORT 53 -> 5353) ---
        dns_redirect="$(nv singbox_dns_redirect)"
        [ -z "$dns_redirect" ] && dns_redirect="0" # Mặc định là Tắt nếu chưa chọn

        if [ "$dns_redirect" = "1" ]; then
            log "Đã BẬT công tắc: Tự động chuyển hướng DNS (Port 53 -> 5353)..."
            iptables -t nat -N SINGBOX_DNS 2>/dev/null
            iptables -t nat -F SINGBOX_DNS 2>/dev/null
            iptables -t nat -A SINGBOX_DNS -p udp --dport 53 -j REDIRECT --to-ports 5353
            iptables -t nat -A SINGBOX_DNS -p tcp --dport 53 -j REDIRECT --to-ports 5353
            while iptables -t nat -D PREROUTING -i br0 -j SINGBOX_DNS 2>/dev/null; do :; done
            iptables -t nat -I PREROUTING -i br0 -j SINGBOX_DNS 2>/dev/null
        else
            log "Công tắc Chuyển hướng DNS đang TẮT (Dùng DNS mặc định của Router)."
        fi

        log "Kích hoạt TProxy IPSet toàn mạng LAN + Bypass Tailscale thành công!"
    else
        # Mixed mode (hoac Custom JSON): khong dung TPROXY, va Chuyen huong
        # DNS (53->5353) cung KHONG duoc ap dung o day vi chi co dns-in o
        # TProxy mode. clean_iptables() se don sach moi rule TPROXY/redirect
        # con sot lai tu lan chay TProxy truoc do (neu co).
        clean_iptables
    fi
}

clean_iptables() {
    while iptables -t mangle -D PREROUTING -i br0 -j SINGBOX 2>/dev/null; do :; done
    iptables -t mangle -F SINGBOX 2>/dev/null
    iptables -t mangle -X SINGBOX 2>/dev/null

    # Xóa NAT REDIRECT DNS
    while iptables -t nat -D PREROUTING -i br0 -j SINGBOX_DNS 2>/dev/null; do :; done
    iptables -t nat -F SINGBOX_DNS 2>/dev/null
    iptables -t nat -X SINGBOX_DNS 2>/dev/null

    while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
    ip route del local default dev lo table 100 2>/dev/null
    ipset destroy singbox_bypass 2>/dev/null
}

# --- CƠ CHẾ GHI CRON TRỰC TIẾP VÀO FILE PADAVAN ---
install_cron() {
    cron_cmd="0 4 * * * /usr/bin/singbox.sh update_sub #$CRON_TAG"
    
    mkdir -p "$(dirname "$CRON_FILE")" 2>/dev/null
    touch "$CRON_FILE" 2>/dev/null
    
    # Xóa dòng cũ nếu có
    sed -i "/$CRON_TAG/d" "$CRON_FILE" 2>/dev/null
    
    # Ghi dòng lịch chạy mới
    echo "$cron_cmd" >> "$CRON_FILE"
    
    # Báo crond reload lại cấu hình
    killall -HUP crond 2>/dev/null
    log "Đã bật lịch tự động cập nhật Sub (04:00 mỗi ngày vào file $CRON_FILE)"
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
            log "update_sub: lần cập nhật gần nhất cách đây $((elapsed / 3600))h, chưa đủ 3 ngày -> bỏ qua"
            return 0
        fi
    fi

    sb_mode="$(nv singbox_mode)"
    case "$sb_mode" in
        0|1) ;;
        *)
            log "update_sub: chỉ hỗ trợ tự động gộp Sub ở Mode 1/2 - Mode 3 dùng JSON tùy chỉnh nên bỏ qua"
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
        log "===== Cập nhật Subscription THẤT BẠI - giữ nguyên mốc thời gian cũ để thử lại ====="
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
                log "CẢNH BÁO: Mode 3 (Custom JSON) nhưng $CFG_PATH rỗng - hãy dán config vào ô Raw JSON trên webui rồi Apply lại."
            elif [ -f "$CFG_MARKER" ] && [ ! "$CFG_PATH" -nt "$CFG_MARKER" ]; then
                # $CFG_PATH chua duoc dung (mtime) ke tu lan generate_config()
                # tu dong sinh gan nhat -> day van la config cua Mode 0/1 cu,
                # KHONG phai JSON tuy chinh that su ban da dan+luu. Neu cu
                # chay tiep, sing-box se khoi dong voi inbound/route cua mode
                # cu trong khi iptables TPROXY da bi go bo o Mode 3 -> process
                # song nhung khong nhan duoc traffic nao, nhin giong "mat mang".
                log "CẢNH BÁO: Mode 3 (Custom JSON) nhưng $CFG_PATH vẫn là config TỰ ĐỘNG SINH từ Mode Mixed/TProxy trước đó, CHƯA được thay bằng JSON tùy chỉnh thật. Vào WebUI, dán JSON thật vào ô Raw Config rồi Apply lại trước khi dùng Mode 3 - nếu không sing-box sẽ chạy nhưng KHÔNG nhận được traffic nào (vì iptables TPROXY đã bị gỡ bỏ ở Mode 3)."
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
            fi
            ;;
    esac
}

install_watchdog() {
    [ ! -f "$WATCHDOG_FILE" ] && return
    sed -i '/sing-box/d' "$WATCHDOG_FILE" 2>/dev/null
    cat >> "$WATCHDOG_FILE" <<-EOF
[ -z "\`pidof sing-box\`" ] && $0 start #sing-box_watchdog
$0 fix_resolv_conf #sing-box_watchdog
	EOF
}

remove_watchdog() {
    [ -f "$WATCHDOG_FILE" ] && sed -i '/sing-box/d' "$WATCHDOG_FILE" 2>/dev/null
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
    # Goi ham nay o ca start() lan 1 dong watchdog dinh ky (khong chi luc
    # start), vi PPPoE/DHCP client co the tu ghi de lai resolv.conf khi
    # WAN reconnect ma khong lien quan gi toi viec sing-box co restart hay
    # khong - neu chi sua luc start() thi giua 2 lan restart, dong nay co
    # the bi WAN reconnect ghi de lai ma khong ai phat hien.
    if [ -f /etc/resolv.conf ] && grep -q "^nameserver 127.0.0.1$" /etc/resolv.conf; then
        sed -i '/^nameserver 127.0.0.1$/d' /etc/resolv.conf
        log "Da go nameserver 127.0.0.1 khoi /etc/resolv.conf de tranh router tu dinh fake-ip"
    fi
}

start() {
    if [ "$(nv singbox_enable)" != "1" ]; then
        log "singbox_enable=0 -> khong khoi dong, chuyen sang stop() + don RAM tmpfs"
        stop purge
        return 0
    fi

    if is_running; then
        log "Already running, skip"
        return 0
    fi

    log "Starting..."
    rotate_log
    mkdir -p "$WORK_DIR"

    # KHÔNG xóa cache.db khi start: cache_file lưu bảng fake-ip <-> domain thật.
    # Nếu xóa mỗi lần start, client còn giữ fake-ip cũ trong DNS cache (TTL 600s)
    # sẽ bị lỗi "missing fakeip record" và rớt kết nối cho tới khi domain đó
    # được resolve lại. Chỉ nên xóa cache thủ công khi thực sự cần debug.

    fix_resolv_conf

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
        log "Process exited immediately after start - check config syntax"
        return 1
    fi
    log "Process started (PID $(pidof sing-box))"

    apply_iptables_mode
    install_watchdog
    sync_cron_state
    return 0
}

stop() {
    # $1 = "purge" -> don sach ca cache RAM tmpfs (binary, dashboard, cache.db,
    # group cache), dung khi tat han sing-box (singbox_enable=0). Restart()
    # thuong (doi mode, cap nhat sub, watchdog hoi phuc) KHONG purge, de giu
    # cache cho lan khoi dong lai sau nhanh hon, khong phai tai lai tu GitHub.
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
        log "Force killing remaining sing-box process..."
        killall -9 sing-box 2>/dev/null
    fi

    if [ "$purge" = "purge" ]; then
        log "Đang dọn cache RAM (tmpfs /tmp/sing-box): binary, dashboard, cache.db, group cache..."
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

case "$1" in
    start)      start ;;
    stop)       stop ;;
    restart)    restart ;;
    status)     status ;;
    update_sub) rotate_log; update_sub "$2" ;;
    fix_resolv_conf) fix_resolv_conf ;;
    *) echo "Usage: $0 {start|stop|restart|status|update_sub [force]|fix_resolv_conf}" ;;
esac
