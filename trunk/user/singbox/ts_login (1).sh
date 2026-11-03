#!/bin/sh
# ==============================================================================
# ts_login.sh - Lấy link đăng nhập Tailscale (endpoint trong sing-box)
# rồi trả mức log về warn để log không phình to.
#
#   ts_login.sh          Bật log info, khởi động lại sing-box, chờ và in link
#   ts_login.sh done     Đăng nhập xong -> xoá log, trả về warn, khởi động lại
#   ts_login.sh status   Xem mức log hiện tại và bộ hẹn giờ tự trả về warn
#
# Nếu quên chạy "done", sau AUTO_REVERT giây (mặc định 15 phút) script tự trả
# log về warn, nên log không bị kẹt ở info.
# ==============================================================================

SB="${SB:-/usr/bin/singbox.sh}"
LOG="${LOG:-/tmp/singbox.log}"
CFG="${CFG:-/etc/storage/singbox.conf}"
PIDF="${PIDF:-/tmp/ts_login.pid}"
LAST_MODE_FILE="${LAST_MODE_FILE:-/tmp/sing-box/.last_mode_memlimit}"
OFF=0
WAIT_LINK="${WAIT_LINK:-90}"        # số giây chờ link xuất hiện
AUTO_REVERT="${AUTO_REVERT:-900}"   # số giây trước khi tự trả log về warn
FINAL_LEVEL="warn"

nv() { nvram get "$1" 2>/dev/null; }

set_level() {
    nvram set singbox_log_level="$1"
    nvram commit >/dev/null 2>&1
}

cfg_level() {
    grep '"level"' "$CFG" 2>/dev/null | head -n 1 | sed 's/.*"level"[^"]*"\([a-z]*\)".*/\1/'
}

cancel_timer() {
    [ -f "$PIDF" ] && kill "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
    rm -f "$PIDF"
}

find_link() {
    # Chỉ đọc phần log ghi SAU lúc khởi động lại (tránh link cũ đã hết hạn).
    # URL đăng nhập có dạng .../a/<id> (Tailscale) hoặc .../register/<id> (Headscale)
    sz="$(wc -c < "$LOG" 2>/dev/null)"
    [ -z "$sz" ] && sz=0
    [ "$sz" -lt "$OFF" ] && OFF=0
    l="$(tail -c +"$((OFF + 1))" "$LOG" 2>/dev/null | grep -i -E 'ts-ep|tailscale' \
        | grep -o -E 'https?://[^ "<>]+/(a|register)/[^ "<>]+' | tail -n 1)"
    [ -z "$l" ] && l="$(tail -c +"$((OFF + 1))" "$LOG" 2>/dev/null \
        | grep -o -E 'https://login\.tailscale\.com/[^ "<>]+' | tail -n 1)"
    echo "$l"
}

cmd_start() {
    if [ "$(nv singbox_ts_enable)" != "1" ]; then
        echo "Tailscale chưa được bật (singbox_ts_enable != 1)."
        echo "Bật 'Bật Tailscale (Native)' trên giao diện, bấm Apply rồi chạy lại."
        exit 1
    fi
    if [ -n "$(nv singbox_ts_authkey)" ]; then
        echo "Ô Auth Key đang có giá trị -> sing-box dùng key đó và sẽ KHÔNG in link."
        echo "Muốn lấy link thì xoá key trước:"
        echo "  nvram set singbox_ts_authkey= ; nvram commit"
        exit 1
    fi

    cancel_timer
    OFF="$(wc -c < "$LOG" 2>/dev/null)"
    [ -z "$OFF" ] && OFF=0
    set_level info
    # singbox.sh bỏ qua việc restart nếu cấu hình không đổi (hot-reload). Xoá dấu
    # trạng thái để buộc restart thật, khi đó endpoint Tailscale mới in lại link.
    rm -f "$LAST_MODE_FILE"
    echo "Đang khởi động lại sing-box với log info..."
    "$SB" restart >/dev/null 2>&1

    lv="$(cfg_level)"
    if [ "$lv" != "info" ]; then
        echo "CẢNH BÁO: cấu hình đang có mức log '$lv', chưa phải info."
        echo "Có thể chế độ chạy dùng JSON thủ công nên script không sinh lại cấu hình."
    fi

    # Hẹn giờ tự trả log về warn, tránh kẹt ở info nếu quên chạy "done"
    ( sleep "$AUTO_REVERT"; sh "$0" done auto ) >/dev/null 2>&1 &
    echo $! > "$PIDF"

    echo "Đang chờ link (tối đa ${WAIT_LINK}s)..."
    n=0
    link=""
    while [ "$n" -lt "$WAIT_LINK" ]; do
        link="$(find_link)"
        [ -n "$link" ] && break
        sleep 3
        n=$((n + 3))
    done

    if [ -n "$link" ]; then
        echo ""
        echo "Mở link này để đăng nhập:"
        echo "$link"
        echo ""
        echo "Đăng nhập xong thì chạy:  sh $0 done"
        echo "(Không chạy thì sau $((AUTO_REVERT / 60)) phút script tự trả log về $FINAL_LEVEL.)"
    else
        echo ""
        echo "Chưa thấy link sau ${WAIT_LINK}s. Có thể router đã đăng nhập sẵn,"
        echo "hoặc endpoint Tailscale lỗi. Xem các dòng liên quan:"
        echo "  grep -i -E 'tailscale|ts-ep|error|fatal' $LOG | head -20"
        echo "Log vẫn ở info; script sẽ tự trả về $FINAL_LEVEL sau $((AUTO_REVERT / 60)) phút."
        exit 2
    fi
}

cmd_done() {
    [ "$1" = "auto" ] || cancel_timer
    rm -f "$PIDF"
    set_level "$FINAL_LEVEL"
    : > "$LOG"
    "$SB" restart >/dev/null 2>&1
    logger -t ts_login "Đã trả log sing-box về $FINAL_LEVEL"
    echo "Đã trả log về $FINAL_LEVEL và xoá log cũ."
}

cmd_status() {
    echo "Mức log (nvram): $(nv singbox_log_level)"
    echo "Mức log (cấu hình đang dùng): $(cfg_level)"
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
        echo "Bộ hẹn giờ tự trả về $FINAL_LEVEL: đang chạy"
    else
        echo "Bộ hẹn giờ tự trả về $FINAL_LEVEL: không chạy"
    fi
}

case "$1" in
    ""|start) cmd_start ;;
    done)     cmd_done "$2" ;;
    status)   cmd_status ;;
    *)        echo "Cách dùng: $0 [start|done|status]" ;;
esac
