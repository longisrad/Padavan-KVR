#!/bin/sh
# AdGuardHome lifecycle manager - written from scratch for Padavan-KVR (NEWIFI3)
# Scope: download/run/stop the binary + redirect DNS. All AGH settings (filters,
# upstream DNS, whitelist...) are configured through AGH's own web dashboard.

BIN_DIR="/tmp/AdGuardHome"
BIN_PATH="$BIN_DIR/AdGuardHome"
CFG_DIR="/etc/storage/AdGuardHome"
CFG_PATH="$CFG_DIR/AdGuardHome.yaml"
AGH_PORT=5335
GH_API="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
GH_DL="https://github.com/AdguardTeam/AdGuardHome/releases/download"
ARCH="AdGuardHome_linux_mipsle_softfloat.tar.gz"
LOG_TAG="AdGuardHome"
WATCHDOG_FILE="/tmp/script/_opt_script_check"

log() {
    logger -t "$LOG_TAG" "$1"
}

is_running() {
    [ -n "$(pidof AdGuardHome)" ]
}

fetch_latest_tag() {
    tag="$(curl -sk --connect-timeout 5 "$GH_API" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)"
    [ -z "$tag" ] && tag="v0.107.78"
    echo "$tag"
}

download_binary() {
    tag="$(fetch_latest_tag)"
    log "Downloading AdGuardHome ${tag}..."
    mkdir -p "$BIN_DIR"
    rm -rf "$BIN_DIR/_dl"
    mkdir -p "$BIN_DIR/_dl"

    url="${GH_DL}/${tag}/${ARCH}"
    archive="$BIN_DIR/_dl/agh.tar.gz"

    curl -Lksfo "$archive" --connect-timeout 10 --retry 2 --max-time 120 "$url" \
        || wget --no-check-certificate -T 20 -t 2 -q -O "$archive" "$url"

    size="$(wc -c < "$archive" 2>/dev/null)"
    if [ -z "$size" ] || [ "$size" -lt 1000000 ]; then
        log "Download failed or incomplete (size=${size:-0} bytes)"
        rm -rf "$BIN_DIR/_dl"
        return 1
    fi

    tar -xzf "$archive" -C "$BIN_DIR/_dl" 2>/dev/null
    extracted="$(find "$BIN_DIR/_dl" -type f -name AdGuardHome | head -n1)"
    if [ -z "$extracted" ]; then
        log "Archive extracted but binary not found inside"
        rm -rf "$BIN_DIR/_dl"
        return 1
    fi

    mv "$extracted" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    rm -rf "$BIN_DIR/_dl"

    if [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -lt 1 ]; then
        log "Downloaded binary failed sanity check"
        rm -f "$BIN_PATH"
        return 1
    fi

    log "AdGuardHome ${tag} ready at $BIN_PATH"
    return 0
}

ensure_binary() {
    if [ -x "$BIN_PATH" ] && [ "$("$BIN_PATH" --version 2>&1 | wc -l)" -ge 1 ]; then
        return 0
    fi
    rm -f "$BIN_PATH"
    download_binary
}

lan_ips() {
    ifconfig br0 2>/dev/null | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}'
}

dnsmasq_forward_add() {
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#'"$AGH_PORT"'$/d' /etc/storage/dnsmasq/dnsmasq.conf
    printf 'no-resolv\nserver=127.0.0.1#%s\n' "$AGH_PORT" >> /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
    log "dnsmasq now forwards to AdGuardHome (port $AGH_PORT)"
}

dnsmasq_forward_del() {
    sed -i '/^no-resolv$/d; /^server=127.0.0.1#'"$AGH_PORT"'$/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

redirect_add() {
    for ip in $(lan_ips); do
        iptables -t nat -A PREROUTING -d "$ip" -p udp --dport 53 -j REDIRECT --to-ports $AGH_PORT 2>/dev/null
        iptables -t nat -A PREROUTING -d "$ip" -p tcp --dport 53 -j REDIRECT --to-ports $AGH_PORT 2>/dev/null
    done
    log "DNS redirect enabled (53 -> $AGH_PORT)"
}

redirect_del() {
    for ip in $(lan_ips); do
        iptables -t nat -D PREROUTING -d "$ip" -p udp --dport 53 -j REDIRECT --to-ports $AGH_PORT 2>/dev/null
        iptables -t nat -D PREROUTING -d "$ip" -p tcp --dport 53 -j REDIRECT --to-ports $AGH_PORT 2>/dev/null
    done
}

apply_redirect_mode() {
    mode="$(nvram get adg_redirect)"
    # Clear any previous mode's config first, then apply the selected one
    dnsmasq_forward_del
    redirect_del
    case "$mode" in
        1)
            if wait_for_port; then
                dnsmasq_forward_add
            else
                log "WARNING: AGH did not open port $AGH_PORT in time, dnsmasq forwarding not applied"
            fi
            ;;
        2)
            if wait_for_port; then
                redirect_add
            else
                log "WARNING: AGH did not open port $AGH_PORT in time, DNS redirect not applied"
            fi
            ;;
        *)
            log "DNS redirect mode: None"
            ;;
    esac
}

wait_for_port() {
    tries=0
    while [ $tries -lt 10 ]; do
        netstat -uln 2>/dev/null | grep -q ":$AGH_PORT " && return 0
        sleep 1
        tries=$((tries + 1))
    done
    return 1
}

install_watchdog() {
    [ ! -f "$WATCHDOG_FILE" ] && return
    sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
    cat >> "$WATCHDOG_FILE" <<-EOF
[ -z "\`pidof AdGuardHome\`" ] && /usr/bin/adguardhome.sh start #${LOG_TAG}_watchdog
	EOF
}

remove_watchdog() {
    [ -f "$WATCHDOG_FILE" ] && sed -Ei "/${LOG_TAG}_watchdog/d" "$WATCHDOG_FILE"
}

start() {
    if is_running; then
        log "Already running, skip"
        return 0
    fi

    log "Starting..."
    mkdir -p "$CFG_DIR"

    if ! ensure_binary; then
        log "Cannot start: no working binary"
        return 1
    fi

    if [ -s "$CFG_PATH" ]; then
        "$BIN_PATH" -c "$CFG_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    else
        # First run: AGH serves its own setup wizard on :3000, will write
        # $CFG_PATH itself once the user completes setup through the dashboard.
        "$BIN_PATH" -w "$CFG_DIR" --no-check-update >/dev/null 2>&1 &
    fi

    sleep 3
    if ! is_running; then
        log "Process exited immediately after start, check binary/config"
        return 1
    fi
    log "Process started (PID $(pidof AdGuardHome))"

    apply_redirect_mode

    install_watchdog
    nvram set adg_enable=1
    return 0
}

stop() {
    log "Stopping..."
    remove_watchdog
    dnsmasq_forward_del
    redirect_del
    killall -9 AdGuardHome 2>/dev/null
    nvram set adg_enable=0
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
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
