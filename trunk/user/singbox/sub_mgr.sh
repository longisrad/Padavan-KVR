#!/bin/sh
# /etc_ro/singbox/sub_mgr.sh - Helper script xử lý danh sách sub /etc/storage/singbox_sub.json

FILE="/etc/storage/singbox_sub.json"
JQ_BIN="/usr/bin/jq"

log() { logger -t "sub_mgr" "$1"; }

[ ! -f "$FILE" ] && echo "[]" > "$FILE"

# Cần jq cho mọi thao tác sửa danh sách; báo lỗi thay vì im lặng
need_jq() {
    [ -x "$JQ_BIN" ] && return 0
    log "LỖI: không tìm thấy $JQ_BIN, không thể sửa danh sách sub"
    echo "jq not found" >&2
    exit 1
}

# Ghi kết quả jq an toàn: chỉ thay file khi jq chạy thành công
jq_edit() {
    if "$JQ_BIN" "$@" "$FILE" > "${FILE}.tmp" 2>/dev/null; then
        mv -f "${FILE}.tmp" "$FILE"
        # Lưu xuống flash (Padavan) nếu có công cụ
        [ -x /sbin/mtd_storage.sh ] && /sbin/mtd_storage.sh save >/dev/null 2>&1
        return 0
    fi
    rm -f "${FILE}.tmp"
    log "LỖI: không sửa được $FILE (file hỏng hoặc chỉ số sai)"
    return 1
}

# Chỉ số phải là số nguyên không âm
check_idx() {
    case "$1" in ''|*[!0-9]*) echo "invalid index" >&2; exit 1 ;; esac
}

case "$1" in
    add)
        name="$2"
        url="$3"
        [ -z "$url" ] && exit 1
        [ -z "$name" ] && name="Group"
        need_jq
        jq_edit --arg n "$name" --arg u "$url" '. + [{"enabled": true, "name": $n, "url": $u}]'
        ;;
    del)
        idx="$2"
        check_idx "$idx"
        need_jq
        jq_edit "del(.[$idx])"
        ;;
    toggle)
        idx="$2"
        [ -z "$idx" ] && idx=0
        check_idx "$idx"
        need_jq
        # Đảo trạng thái: đang tắt (false) -> bật; còn lại -> tắt
        jq_edit ".[$idx].enabled = (.[$idx].enabled == false)"
        ;;
    preset)
        # Link sing-box JSON (không cần lua để chuyển đổi). Nguồn: Au1rxx/free-vpn-subscriptions
        cat > "$FILE" <<-EOF
[
  {"enabled": true, "name": "VN", "url": "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/by-country/singbox-VN.json"},
  {"enabled": true, "name": "SG", "url": "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/by-country/singbox-SG.json"},
  {"enabled": true, "name": "HK", "url": "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/by-country/singbox-HK.json"},
  {"enabled": true, "name": "JP", "url": "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/by-country/singbox-JP.json"}
]
EOF
        [ -x /sbin/mtd_storage.sh ] && /sbin/mtd_storage.sh save >/dev/null 2>&1
        ;;
esac
