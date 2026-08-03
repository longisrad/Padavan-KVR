#!/bin/sh
# AdGuardHome Comprehensive Manager for Padavan
# Logic: 
# - Tự động tải/kiểm tra binary.
# - Đồng bộ biến NVRAM WebUI với file cấu hình YAML (chỉ đồng bộ Port DNS).
# - Hỗ trợ Setup Wizard lần đầu và tự động dẹp đường (kill dnsmasq).
# - Hỗ trợ phân giải tên miền nội bộ và Tailscale.

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

# Cấu hình NVRAM
ENABLE=$(nvram get adg_enable)
MODE=$(nvram get adg_redirect) # 1: dnsmasq 53 -> AGH; 2: AGH 53 -> dnsmasq

log() { logger -t "$LOG_TAG" "$1"; }
is_running() { [ -n "$(pidof AdGuardHome)" ]; }

# --- 1. QUẢN LÝ BINARY ---
ensure_binary() {
    if [ -x "$BIN_PATH" ] && [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    log "Binary missing or invalid, downloading latest..."
    mkdir -p "$BIN_DIR/_dl"
    url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    curl -Lksfo "$BIN_DIR/_dl/agh.tar.gz" "$url" --connect-timeout 10
    tar -xzf "$BIN_DIR/_dl/agh.tar.gz" -C "$BIN_DIR/_dl"
    mv "$(find "$BIN_DIR/_dl" -type f -name AdGuardHome | head -n1)" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/_dl"
}

# --- 2. ĐỒNG BỘ CẤU HÌNH MẠNG (dnsmasq) ---
dnsmasq_sync() {
    # Làm sạch config dnsmasq cũ
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    
    if [ "$MODE" = "1" ]; then
        log "Mode 1: dnsmasq(53) -> AGH(5335)"
        printf 'no-resolv\nserver=127.0.0.1#5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    elif [ "$MODE" = "2" ]; then
        log "Mode 2: AGH(53) -> dnsmasq(5335)"
        echo "port=5335" >> /etc/storage/dnsmasq/dnsmasq.conf
        killall dnsmasq 2>/dev/null # Buộc nhả cổng 53 ngay lập tức
    fi
    /sbin/restart_dhcpd
}

# --- 3. ĐỒNG BỘ FILE YAML VỚI WEBUI (Tránh sập mạng) ---
yaml_sync() {
    # Nếu chưa có file config, mồi file cơ bản để bypass Setup Wizard nếu muốn 
    # hoặc để AGH khởi động đúng cổng bạn định nghĩa
    if [ ! -s "$CFG_PATH" ]; then
        log "Tạo cấu hình mồi cho lần đầu chạy..."
        mkdir -p "$CFG_DIR"
        cat > "$CFG_PATH" <<EOF
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts: [0.0.0.0]
  port: 5335
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - [/lan/]127.0.0.1:5335
    - [/ts.net/]100.100.100.100
users:
  - name: admin
    password: \$2b\$12\$zgC5mg2IyANRLOi8OHgVvePjzQ0s6uIgjlG1P3.nnzQ3ACXD9czYC
schema_version: 28
EOF
    fi

    # ĐỒNG BỘ CỔNG: Đây là phần quan trọng nhất để WebUI và AGH khớp nhau
    local target_p=5335
    [ "$MODE" = "2" ] && target_p=53
    
    # Chỉ sửa dòng port của phần dns, không đụng vào các phần khác
    sed -i "/dns:/,/port:/ s/port: [0-9]*/port: $target_p/" "$CFG_PATH"
    log "Đồng bộ YAML Port DNS: $target_p"
}

# --- 4. QUY TRÌNH KHỞI ĐỘNG ---
start() {
    if [ "$ENABLE" != "1" ]; then
        stop
        return 0
    fi

    log "Đang khởi động AdGuard Home..."
    ensure_binary || return 1

    # Đồng bộ cổng DNS giữa NVRAM và YAML trước khi khởi động
    yaml_sync
    
    # Đồng bộ dnsmasq và xử lý xung đột cổng
    dnsmasq_sync
    sleep 2

    # Khởi chạy binary
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "Khởi động thành công. WebUI: :3000"
        # Watchdog
        sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
        echo "[ -z \"\`pidof AdGuardHome\`\" ] && $0 start #${LOG_TAG}_watchdog" >> "$WATCHDOG_FILE"
    else
        log "Lỗi: Không thể khởi động AGH. Đang khôi phục dnsmasq..."
        sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
    fi
}

stop() {
    log "Đang dừng AdGuard Home..."
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE" 2>/dev/null
    killall -9 AdGuardHome 2>/dev/null
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    status) is_running && echo "running" || echo "stopped" ;;
esac
