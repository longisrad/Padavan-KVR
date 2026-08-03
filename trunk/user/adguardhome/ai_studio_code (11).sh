#!/bin/sh
# AdGuardHome manager for Padavan - Build Version
# Logic: Script chỉ xử lý dnsmasq và tải binary. Cấu hình DNS port do người dùng tự chỉnh trong Dashboard AGH.

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
LOG_TAG="AdGuardHome"

# Thông tin tải về
GH_DL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_mipsle_softfloat.tar.gz"

ENABLE=$(nvram get adg_enable)
MODE=$(nvram get adg_redirect) # Mode 1: dnsmasq 53, Mode 2: AGH 53

log() { logger -t "$LOG_TAG" "$1"; }
is_running() { [ -n "$(pidof AdGuardHome)" ]; }

ensure_binary() {
    if [ -x "$BIN_PATH" ] && [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    log "Binary missing, downloading..."
    mkdir -p "$BIN_DIR/_dl"
    curl -Lksfo "$BIN_DIR/_dl/agh.tar.gz" "$GH_DL"
    tar -xzf "$BIN_DIR/_dl/agh.tar.gz" -C "$BIN_DIR/_dl"
    mv "$(find "$BIN_DIR/_dl" -type f -name AdGuardHome | head -n1)" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/_dl"
}

dnsmasq_apply() {
    # Làm sạch config dnsmasq
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#/d; /^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
    
    if [ "$MODE" = "1" ]; then
        log "Mode 1: dnsmasq(53) -> AGH(5335). Hãy đảm bảo Dashboard AGH cũng để cổng 5335."
        printf 'no-resolv\nserver=127.0.0.1#5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
    elif [ "$MODE" = "2" ]; then
        log "Mode 2: AGH(53) -> dnsmasq(5335). Hãy đảm bảo Dashboard AGH cũng để cổng 53."
        echo "port=5335" >> /etc/storage/dnsmasq/dnsmasq.conf
        killall dnsmasq 2>/dev/null
    fi
    /sbin/restart_dhcpd
}

start() {
    [ "$ENABLE" != "1" ] && { stop; return 0; }

    ensure_binary || return 1
    mkdir -p "$CFG_DIR"

    # NẾU CHƯA CÓ CONFIG -> MỒI ĐỂ VÀO SETUP WIZARD
    if [ ! -s "$CFG_PATH" ]; then
        log "Lần đầu: Mồi config. Truy cập http://$(nvram get lan_ipaddr):3000 để setup."
        # Giết dnsmasq tạm thời để Setup Wizard cổng 53 không bị lỗi
        killall dnsmasq 2>/dev/null
        cat > "$CFG_PATH" <<EOF
http:
  address: 0.0.0.0:3000
dns:
  bind_hosts: [0.0.0.0]
  port: 5335
EOF
    fi

    # Thực thi cấu hình mạng dnsmasq
    dnsmasq_apply
    sleep 2

    # Chạy AGH (Không can thiệp vào file yaml nữa, AGH tự đọc cấu hình Dashboard đã lưu)
    "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    
    sleep 5
    if is_running; then
        log "AdGuard Home đã chạy."
    else
        log "Lỗi khởi động. Hãy kiểm tra xem cổng DNS trong Dashboard có khớp với Mode đã chọn không."
    fi
}

stop() {
    log "Stopping AdGuard Home..."
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