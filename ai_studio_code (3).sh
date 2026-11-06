#!/bin/bash
set -e

R="/opt/rt-n56u/trunk"
TNAME="NEWIFI3"

echo "====================================================="
echo ">>> 1. CHỈNH SỬA BỘ NHỚ RAM, STORAGE 18MB VÀ WIFI"
echo "====================================================="
sed -i 's/^CONFIG_MTD_STORE_PART_SIZ=0x200000/CONFIG_MTD_STORE_PART_SIZ=0x1200000/' $R/configs/boards/$TNAME/kernel-3.4.x.config
sed -i 's/size_etc="6M"/size_etc="18M"/g' $R/user/scripts/dev_init.sh
sed -i 's/size_tmp="24M"/size_tmp="160M"/' $R/user/scripts/dev_init.sh
sed -i 's/mtd_part_size=65536/mtd_part_size=18874368/g' $R/user/scripts/mtd_storage.sh
sed -i 's/\(DEF_WLAN_5G_CC[[:space:]]*\)"US"/\1"CN"/' $R/user/shared/defaults.h

# Fix dosfstools timestamps
D=$R/user/dosfstools/dosfstools-4.2
if [ -d "$D" ]; then
  touch $D/aclocal.m4; sleep 1
  touch $D/configure $D/config.h.in 2>/dev/null || true; sleep 1
  find $D -name Makefile.in -exec touch {} +
fi

echo "====================================================="
echo ">>> 2. TẢI VÀ VÁ KERNEL CAKE + IPROUTE2 5.12.0"
echo "====================================================="
git clone --depth=1 https://github.com/TW641/padavan-ng /tmp/tw
T=/tmp/tw/trunk
git clone --depth=1 https://github.com/TW641/sch_cake /tmp/sch_cake
PORT="/tmp/sch_cake/Padavan 3.4.113"

F=$R/linux-3.4.x/net/sched/sch_cake.c
if [ -f "$PORT/sch_cake.c" ]; then
  cp -f "$PORT/sch_cake.c" $F
else
  cp -f $T/linux-3.4.x/net/sched/sch_cake.c $F
fi

cat > /tmp/cake_compat.h <<'CEOF'
/* CAKE_COMPAT34 */
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/in.h>
#include <linux/vmalloc.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
static inline void cake_kvfree(const void *p)
{ if (is_vmalloc_addr(p)) vfree(p); else kfree(p); }
/*KEYS_BEGIN*/
struct cake_flow_keys {
	__be32 src;
	__be32 dst;
	union { __be32 ports; __be16 port16[2]; };
	u16 thoff;
	u16 n_proto;
	u8 ip_proto;
};
/*KEYS_END*/
static bool cake_flow_dissect(const struct sk_buff *cskb, struct cake_flow_keys *k)
{
	struct sk_buff *skb = (struct sk_buff *)cskb;
	int off, hl;
	u8 proto;
	memset(k, 0, sizeof(*k));
	k->n_proto = ntohs(skb->protocol);
	if (skb->protocol == htons(ETH_P_IP)) {
		const struct iphdr *iph;
		if (!pskb_may_pull(skb, sizeof(*iph))) return false;
		iph = ip_hdr(skb);
		hl = iph->ihl * 4;
		k->src = iph->saddr; k->dst = iph->daddr;
		proto = iph->protocol;
		off = skb_network_offset(skb) + hl;
		if (iph->frag_off & htons(IP_MF | IP_OFFSET)) proto = 0;
	} else if (skb->protocol == htons(ETH_P_IPV6)) {
		const struct ipv6hdr *ip6;
		if (!pskb_may_pull(skb, sizeof(*ip6))) return false;
		ip6 = ipv6_hdr(skb);
		k->src = ip6->saddr.s6_addr32[0] ^ ip6->saddr.s6_addr32[1] ^ ip6->saddr.s6_addr32[2] ^ ip6->saddr.s6_addr32[3];
		k->dst = ip6->daddr.s6_addr32[0] ^ ip6->daddr.s6_addr32[1] ^ ip6->daddr.s6_addr32[2] ^ ip6->daddr.s6_addr32[3];
		proto = ip6->nexthdr;
		hl = sizeof(*ip6);
		off = skb_network_offset(skb) + hl;
	} else { return false; }
	k->ip_proto = proto;
	k->thoff = off;
	switch (proto) {
	case IPPROTO_TCP:
	case IPPROTO_UDP:
	case IPPROTO_UDPLITE:
	case IPPROTO_SCTP:
	case IPPROTO_DCCP:
		if (pskb_may_pull(skb, off + 4)) k->ports = *(__be32 *)(skb->data + off);
		break;
	}
	return true;
}
CEOF

python3 - <<'PEOF'
import re
p = "/opt/rt-n56u/trunk/linux-3.4.x/net/sched/sch_cake.c"
s = open(p).read()
if "CAKE_COMPAT34" not in s:
    if not re.search(r"#\s*define\s+prandom_u32", s): s = re.sub(r"\bprandom_u32\(\)", "random32()", s)
    if not re.search(r"#\s*define\s+kvfree", s): s = re.sub(r"\bkvfree\(", "cake_kvfree(", s)
    have_keys = re.search(r"^struct\s+flow_keys\s*\{", s, re.M) is not None
    s = re.sub(r"\bstruct flow_keys\b", "struct cake_flow_keys", s)
    s = re.sub(r"\bskb_flow_dissect\(", "cake_flow_dissect(", s)
    compat = open("/tmp/cake_compat.h").read()
    if have_keys:
        compat = compat.replace("/*KEYS_BEGIN*/", "/*").replace("/*KEYS_END*/", "*/")
    last = [m.end() for m in re.finditer(r"^#include[^\n]*\n", s, re.M)][-1]
    s = s[:last] + compat + s[last:]
    open(p, "w").write(s)
PEOF

for f in $T/linux-3.4.x/net/sched/*; do
  b=$(basename "$f")
  [ -f "$f" ] && [ ! -e "$R/linux-3.4.x/net/sched/$b" ] && cp -f "$f" "$R/linux-3.4.x/net/sched/$b" || true
done
grep -q TCA_CAKE_ $R/linux-3.4.x/include/linux/pkt_sched.h || cp -f $T/linux-3.4.x/include/linux/pkt_sched.h $R/linux-3.4.x/include/linux/pkt_sched.h

KC=$R/configs/boards/$TNAME/kernel-3.4.x.config
sed -i '/^CONFIG_NET_SCH_CAKE=/d; /CONFIG_NET_SCH_CAKE is not set/d' $KC
echo "CONFIG_NET_SCH_CAKE=y" >> $KC
for o in NET_SCHED NET_CLS NET_CLS_ACT NET_ACT_MIRRED NET_CLS_U32 NET_SCH_INGRESS IFB; do
  sed -i "/^CONFIG_$o=/d; /^# CONFIG_$o is not set/d" $KC
  echo "CONFIG_$o=y" >> $KC
done
sed -i "/^CONFIG_NET_SCH_FQ_CODEL=/d; /^# CONFIG_NET_SCH_FQ_CODEL is not set/d" $KC
echo "# CONFIG_NET_SCH_FQ_CODEL is not set" >> $KC

TCP=/opt/rt-n56u/toolchain-mipsel/toolchain-3.4.x/bin/mipsel-linux-uclibc-
cp -f $KC $R/linux-3.4.x/.config
yes "" | make -C $R/linux-3.4.x ARCH=mips CROSS_COMPILE=$TCP oldconfig > /dev/null 2>&1 || true
cp -f $R/linux-3.4.x/.config $KC

# iproute2
rm -rf $R/user/iproute2
cp -rf $T/user/iproute2 $R/user/iproute2
python3 - <<'PYEOF'
import re
p = "/opt/rt-n56u/trunk/user/iproute2/iproute2-5.12.0/lib/fs.c"
s = open(p).read()
if "FS_COMPAT_UCLIBC" not in s:
    compat = (
        "\n/* FS_COMPAT_UCLIBC */\n"
        "#include <sys/syscall.h>\n#include <unistd.h>\n#include <fcntl.h>\n"
        "#ifndef __NR_name_to_handle_at\n#define __NR_name_to_handle_at 4339\n#endif\n"
        "#ifndef __NR_open_by_handle_at\n#define __NR_open_by_handle_at 4340\n#endif\n"
        "struct file_handle { unsigned int handle_bytes; int handle_type; unsigned char f_handle[]; };\n"
        "static int name_to_handle_at(int d, const char *n, struct file_handle *h, int *m, int f)\n"
        "{ return syscall(__NR_name_to_handle_at, d, n, h, m, f); }\n"
        "static int open_by_handle_at(int m, struct file_handle *h, int f)\n"
        "{ return syscall(__NR_open_by_handle_at, m, h, f); }\n\n"
    )
    last = [m.end() for m in re.finditer(r"^#include[^\n]*\n", s, re.M)][-1]
    s = s[:last] + compat + s[last:]
    open(p, "w").write(s)
PYEOF

# Đảm bảo Makefile user & user/www có cờ CAKE
grep -q "CONFIG_FIRMWARE_INCLUDE_CAKE" $R/user/Makefile || sed -i '/CONFIG_FIRMWARE_INCLUDE_SINGBOX/a dir_$(CONFIG_FIRMWARE_INCLUDE_CAKE)\t\t+= cake' $R/user/Makefile
grep -q "CONFIG_FIRMWARE_INCLUDE_CAKE" $R/user/www/Makefile || sed -i '/CONFIG_FIRMWARE_INCLUDE_V2RAYA/a ifneq ($(CONFIG_FIRMWARE_INCLUDE_CAKE),y)\n\trm -f $(INSTALLDIR)/www/Advanced_cake.asp\nendif' $R/user/www/Makefile

echo "====================================================="
echo ">>> 3. TỰ ĐỘNG VÁ TẦNG C CHO CAKE SQM"
echo "====================================================="
python3 - <<'EOF'
import os, re

R = "/opt/rt-n56u/trunk"

def patch_file(relpath, pattern, insert_text, after=True):
    filepath = os.path.join(R, relpath) if not relpath.startswith("/") else relpath
    if not os.path.exists(filepath):
        print(f"[-] Không tìm thấy: {relpath}")
        return False
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
    if insert_text.strip() in content:
        print(f"[=] Đã có trong: {relpath}")
        return True
    match = re.search(pattern, content)
    if not match:
        print(f"[!] Không khớp pattern trong: {relpath}")
        return False
    idx = match.end() if after else match.start()
    new_content = content[:idx] + insert_text + content[idx:]
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"[+] Đã vá thành công: {relpath}")
    return True

# 1. Quét và vá RCN_RESTART_CAKE vào TẤT CẢ các file notify_rc.h
rcn_define = '\n#ifndef RCN_RESTART_CAKE\n#define RCN_RESTART_CAKE\t\t"restart_cake"\n#endif\n'
for root, dirs, files in os.walk("/opt/rt-n56u"):
    for file in files:
        if file == "notify_rc.h":
            full_path = os.path.join(root, file)
            patch_file(full_path, r'#endif\s*/\*\s*NOTIFY_RC_H\s*\*\/|#endif', rcn_define, after=False)

# 2. common.h
patch_file("user/httpd/common.h", r'#define\s+EVM_RESTART_SWITCH_VLAN[^\n]*', '\n#define EVM_RESTART_CAKE\t\t\t(1ULL << 16) // CAKE SQM')
patch_file("user/httpd/common.h", r'#define\s+EVT_RESTART_SINGBOX[^\n]*', '\n#define EVT_RESTART_CAKE    \t\t2')

# 3. cflags.mk
patch_file("user/shared/cflags.mk", r'ifeq\s*\(\$\(CONFIG_FIRMWARE_INCLUDE_SINGBOX\),y\)[\s\S]*?endif', '\n\nifeq ($(CONFIG_FIRMWARE_INCLUDE_CAKE),y)\nCFLAGS += -DAPP_CAKE\nendif')

# 4. defaults.c
patch_file("user/shared/defaults.c", r'\{\s*"w_v2raya",\s*"1"\s*\},', '\n\t{ "w_cake", "1" },')
cake_defaults = """
#if defined(APP_CAKE)
\t/* CAKE SQM */
\t{ "cake_enable", "0" },
\t{ "cake_drop_hwnat", "1" },
\t{ "cake_down_bw", "100000" },
\t{ "cake_up_bw", "50000" },
\t{ "cake_flow_mode", "triple-isolate" },
\t{ "cake_diffserv", "diffserv4" },
\t{ "cake_rtt", "internet" },
\t{ "cake_overhead", "none" },
\t{ "cake_ack_filter", "none" },
\t{ "cake_nat", "1" },
\t{ "cake_wash", "1" },
\t{ "cake_custom", "" },
#endif"""
patch_file("user/shared/defaults.c", r'\{\s*"singbox_auto_update",\s*"0"\s*\},', cake_defaults)

# 5. variables.c - ĐẶT variables_CakeConf ĐỘC LẬP NGAY TRƯỚC BẢNG svcLinks[]
var_file = None
for candidate in ["user/httpd/variables.c", "user/httpd/web_variables.c", "user/httpd/common.c"]:
    full_c = os.path.join(R, candidate)
    if os.path.exists(full_c):
        with open(full_c) as f:
            if "variables_Language" in f.read():
                var_file = candidate
                break

cake_vars = """
#if defined(APP_CAKE)
struct variable variables_CakeConf[] = {
\t\t{"cake_enable", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_drop_hwnat", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_down_bw", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_up_bw", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_flow_mode", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_diffserv", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_rtt", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_overhead", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_ack_filter", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_nat", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_wash", "", NULL, EVM_RESTART_CAKE},
\t\t{"cake_custom", "", NULL, EVM_RESTART_CAKE},
\t\t{0,0,0,0}
};
#endif
"""

# Chèn mảng biến CAKE trước struct svcLink svcLinks[] để không bị kẹt trong bất kỳ #if defined nào
patch_file(var_file, r'struct\s+svcLink\s+svcLinks\[\]', cake_vars + "\n", after=False)

patch_file(var_file, r'\{\s*"w_v2raya"[^\n]*\},', '\n\t\t\t{"w_cake", "", NULL, FALSE},')
patch_file(var_file, r'#if\s+defined\(APP_SINGBOX\)[\s\S]*?\{"SingboxConf",\s*variables_SingboxConf\},[\s\S]*?#endif', '\n#if defined(APP_CAKE)\n\t\t{"CakeConf",\t\tvariables_CakeConf},\n#endif')
patch_file(var_file, r'#if\s+defined\(APP_SINGBOX\)[\s\S]*?\{EVM_RESTART_SINGBOX,[^\n]*\},[\s\S]*?#endif', '\n#if defined(APP_CAKE)\n\t\t{EVM_RESTART_CAKE,\t\tEVT_RESTART_CAKE,\t\tRCN_RESTART_CAKE,\t0},\n#endif')

# 6. rc.h
patch_file("user/rc/rc.h", r'#if\s+defined\(APP_SINGBOX\)[\s\S]*?update_singbox_sub\(void\);[\s\S]*?#endif', '\n#if defined(APP_CAKE)\nvoid stop_cake(void);\nvoid start_cake(void);\nvoid restart_cake(void);\n#endif')

# 7. services.c
cake_service_funcs = """
#if defined(APP_CAKE)
void stop_cake(void){ eval("/sbin/cake.sh","stop"); }
void start_cake(void){ if (nvram_get_int("cake_enable") == 1) eval("/sbin/cake.sh","start"); }
void restart_cake(void){ stop_cake(); start_cake(); }
#endif
"""
patch_file("user/rc/services.c", r'#if\s+defined\(APP_WYY\)', cake_service_funcs, after=False)
patch_file("user/rc/services.c", r'#if\s+defined\(APP_SINGBOX\)[\s\S]*?stop_singbox\(\);[\s\S]*?#endif', '\n#if defined(APP_CAKE)\n\tstop_cake();\n#endif')

# 8. rc.c
cake_rc_notify = """#if defined(APP_CAKE)
\t\telse if (strcmp(entry->d_name, RCN_RESTART_CAKE) == 0)
\t\t{
\t\t\trestart_cake();
\t\t}
#endif\n\t\t"""
patch_file("user/rc/rc.c", r'#if\s+defined\(APP_SMARTDNS\)[\s\S]*?RCN_RESTART_SMARTDNS[\s\S]*?#endif', cake_rc_notify, after=False)

# 9. web_ex.c
patch_file("user/httpd/web_ex.c", r'else\s+if\s*\(strcmp\(name,\s*"hostname_check"\)\s*==\s*0\)[\s\S]*?\}', '\n\telse if (strcmp(name, "restart_cake") == 0)\n\t{\n\t\tnotify_rc("restart_cake");\n\t}')
patch_file("user/httpd/web_ex.c", r'#if\s+defined\(APP_SINGBOX\)[\s\S]*?int\s+found_app_singbox\s*=\s*0;[\s\S]*?#endif', '\n#if defined(APP_CAKE)\n\tint found_app_cake = 1;\n#else\n\tint found_app_cake = 0;\n#endif')
patch_file("user/httpd/web_ex.c", r'"function\s+found_app_singbox\(\)\s*\{\s*return\s*%d;\}\\n"', '\n\t\t"function found_app_cake() { return %d;}\\n"')
patch_file("user/httpd/web_ex.c", r'found_app_singbox,', '\n\t\tfound_app_cake,')

# 10. Hook post_wan_script.sh
post_wan = os.path.join(R, "user/scripts/post_wan_script.sh")
if os.path.exists(post_wan):
    with open(post_wan, "r") as f: p_content = f.read()
    if "cake.sh restart" not in p_content:
        with open(post_wan, "a") as f:
            f.write("\n[ -x /sbin/cake.sh ] && /sbin/cake.sh restart\n")

print("=== HOÀN TẤT VÁ TOÀN BỘ TẦNG C CHO CAKE ===")
EOF

echo "====================================================="
echo ">>> 4. THIẾT LẬP FILE .CONFIG CHO FIRMWARE"
echo "====================================================="
cd $R
cp -f configs/templates/$TNAME.config .config
sed -i 's/EVM_RESTART_ALDRIVER/EVM_RESTART_VIRTUALHERE/g' ./user/httpd/common.h

# Dọn dẹp config cũ
sed -i -E '/CONFIG_FIRMWARE_(CPU_900MHZ|CPU_SLEEP|ENABLE_IPV6|ENABLE_USB|ENABLE_UFSD|ENABLE_FAT|ENABLE_EXFAT|ENABLE_EXT2|ENABLE_EXT3|ENABLE_EXT4|ENABLE_XFS|ENABLE_FUSE|ENABLE_SWAP)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_UVC|INCLUDE_HID|INCLUDE_SERIAL|INCLUDE_AUDIO|INCLUDE_XFRM|INCLUDE_QOS|INCLUDE_IMQ|INCLUDE_IFB|INCLUDE_IPSET)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_NFSD|INCLUDE_NFSC|INCLUDE_CIFS|INCLUDE_NTFS_3G|INCLUDE_LPRD|INCLUDE_U2EC|INCLUDE_TCPDUMP|INCLUDE_HDPARM|INCLUDE_PARTED)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_SMBD|INCLUDE_SMBD36|INCLUDE_WINS|INCLUDE_SMBD_SYSLOG|INCLUDE_FTPD|INCLUDE_RPL2TP|INCLUDE_EAP_PEAP|INCLUDE_DDNS_SSL|INCLUDE_HTTPS|INCLUDE_SFTP)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_DROPBEAR|INCLUDE_DROPBEAR_FAST_CODE|INCLUDE_OPENSSH|INCLUDE_OPENVPN|INCLUDE_SSWAN|INCLUDE_OPENSSL_EC|INCLUDE_OPENSSL_EXE)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_XUPNPD|INCLUDE_MINIDLNA|INCLUDE_FIREFLY|INCLUDE_FFMPEG_NEW|INCLUDE_TRANSMISSION|INCLUDE_TRANSMISSION_WEB_CONTROL|INCLUDE_ARIA|INCLUDE_ARIA_WEB_CONTROL|INCLUDE_CURL)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_SCUTCLIENT|INCLUDE_GDUT_DRCOM|INCLUDE_DOGCOM|INCLUDE_MINIEAP|INCLUDE_NJIT_CLIENT|INCLUDE_NAPT66|INCLUDE_SSSERVER)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_SOFTETHERVPN_SERVER|INCLUDE_SOFTETHERVPN_CLIENT|INCLUDE_SOFTETHERVPN_CMD|INCLUDE_DNSFORWARDER|INCLUDE_VLMCSD|INCLUDE_TTYD|INCLUDE_LRZSZ|INCLUDE_HTOP|INCLUDE_NANO)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_IPERF3|INCLUDE_DUMP1090|INCLUDE_RTL_SDR|INCLUDE_MTR|INCLUDE_SOCAT|INCLUDE_SRELAY|INCLUDE_MENTOHUST|INCLUDE_FRPC|INCLUDE_FRPS|INCLUDE_TUNSAFE|INCLUDE_WIREGUARD)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_ZEROTIER|INCLUDE_ALIDDNS|INCLUDE_SHADOWSOCKS|INCLUDE_V2RAY|INCLUDE_XRAY|INCLUDE_TROJAN|INCLUDE_SSOBFS|INCLUDE_NPC|WEBUI_HIDE_VPN|INCLUDE_OPENVPN)/d' .config
sed -i -E '/CONFIG_FIRMWARE_(INCLUDE_TAILSCALE|INCLUDE_ADGUARDHOME|INCLUDE_NATPIERCE|INCLUDE_VNTCLI|INCLUDE_VNTS|INCLUDE_CLOUDFLARED|INCLUDE_LUCKY|INCLUDE_CLOUDFLARE|INCLUDE_EASYTIER|INCLUDE_ALIST|INCLUDE_WXSEND|INCLUDE_UUPLUGIN|INCLUDE_ALDRIVER|INCLUDE_VIRTUALHERE|INCLUDE_WYY|INCLUDE_BAFA|INCLUDE_CADDY|INCLUDE_SMARTDNS|INCLUDE_NETCAT|INCLUDE_MSD_LITE|INCLUDE_SINGBOX|INCLUDE_CAKE)/d' .config

cat >> .config << 'CONFEOF'
CONFIG_FIRMWARE_CPU_900MHZ=y
CONFIG_FIRMWARE_CPU_SLEEP=n
CONFIG_FIRMWARE_ENABLE_IPV6=y
CONFIG_FIRMWARE_ENABLE_USB=y
CONFIG_FIRMWARE_ENABLE_UFSD=y
CONFIG_FIRMWARE_ENABLE_FAT=y
CONFIG_FIRMWARE_ENABLE_EXFAT=y
CONFIG_FIRMWARE_ENABLE_EXT2=y
CONFIG_FIRMWARE_ENABLE_EXT3=y
CONFIG_FIRMWARE_ENABLE_EXT4=y
CONFIG_FIRMWARE_ENABLE_XFS=n
CONFIG_FIRMWARE_ENABLE_FUSE=y
CONFIG_FIRMWARE_ENABLE_SWAP=n
CONFIG_FIRMWARE_INCLUDE_UVC=n
CONFIG_FIRMWARE_INCLUDE_HID=n
CONFIG_FIRMWARE_INCLUDE_SERIAL=y
CONFIG_FIRMWARE_INCLUDE_AUDIO=n
CONFIG_FIRMWARE_INCLUDE_XFRM=n
CONFIG_FIRMWARE_INCLUDE_QOS=y
CONFIG_FIRMWARE_INCLUDE_IMQ=y
CONFIG_FIRMWARE_INCLUDE_IFB=y
CONFIG_FIRMWARE_INCLUDE_IPSET=y
CONFIG_FIRMWARE_INCLUDE_TUNSAFE=y
CONFIG_FIRMWARE_INCLUDE_NFSD=n
CONFIG_FIRMWARE_INCLUDE_CIFS=n
CONFIG_FIRMWARE_INCLUDE_NTFS_3G=n
CONFIG_FIRMWARE_INCLUDE_LPRD=y
CONFIG_FIRMWARE_INCLUDE_U2EC=y
CONFIG_FIRMWARE_INCLUDE_TCPDUMP=y
CONFIG_FIRMWARE_INCLUDE_HDPARM=y
CONFIG_FIRMWARE_INCLUDE_PARTED=y
CONFIG_FIRMWARE_INCLUDE_SMBD=y
CONFIG_FIRMWARE_INCLUDE_SMBD36=y
CONFIG_FIRMWARE_INCLUDE_SMBD_SYSLOG=n
CONFIG_FIRMWARE_INCLUDE_FTPD=y
CONFIG_FIRMWARE_INCLUDE_RPL2TP=n
CONFIG_FIRMWARE_INCLUDE_EAP_PEAP=y
CONFIG_FIRMWARE_INCLUDE_DDNS_SSL=y
CONFIG_FIRMWARE_INCLUDE_HTTPS=y
CONFIG_FIRMWARE_INCLUDE_SFTP=y
CONFIG_FIRMWARE_INCLUDE_DROPBEAR=n
CONFIG_FIRMWARE_INCLUDE_DROPBEAR_FAST_CODE=n
CONFIG_FIRMWARE_INCLUDE_OPENSSH=y
CONFIG_FIRMWARE_INCLUDE_SSWAN=n
CONFIG_FIRMWARE_INCLUDE_OPENSSL_EC=y
CONFIG_FIRMWARE_INCLUDE_OPENSSL_EXE=y
CONFIG_FIRMWARE_INCLUDE_XUPNPD=n
CONFIG_FIRMWARE_INCLUDE_MINIDLNA=n
CONFIG_FIRMWARE_INCLUDE_FIREFLY=n
CONFIG_FIRMWARE_INCLUDE_FFMPEG_NEW=y
CONFIG_FIRMWARE_INCLUDE_TRANSMISSION=n
CONFIG_FIRMWARE_INCLUDE_TRANSMISSION_WEB_CONTROL=n
CONFIG_FIRMWARE_INCLUDE_ARIA=n
CONFIG_FIRMWARE_INCLUDE_ARIA_WEB_CONTROL=n
CONFIG_FIRMWARE_INCLUDE_CURL=y
CONFIG_FIRMWARE_INCLUDE_SCUTCLIENT=n
CONFIG_FIRMWARE_INCLUDE_OPENVPN=y
CONFIG_FIRMWARE_INCLUDE_GDUT_DRCOM=n
CONFIG_FIRMWARE_INCLUDE_DOGCOM=n
CONFIG_FIRMWARE_INCLUDE_MINIEAP=n
CONFIG_FIRMWARE_INCLUDE_NJIT_CLIENT=n
CONFIG_FIRMWARE_INCLUDE_NAPT66=y
CONFIG_FIRMWARE_INCLUDE_SSSERVER=n
CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_SERVER=n
CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_CLIENT=n
CONFIG_FIRMWARE_INCLUDE_SOFTETHERVPN_CMD=n
CONFIG_FIRMWARE_INCLUDE_DNSFORWARDER=n
CONFIG_FIRMWARE_INCLUDE_VLMCSD=n
CONFIG_FIRMWARE_INCLUDE_TTYD=y
CONFIG_FIRMWARE_INCLUDE_LRZSZ=n
CONFIG_FIRMWARE_INCLUDE_HTOP=y
CONFIG_FIRMWARE_INCLUDE_NANO=y
CONFIG_FIRMWARE_INCLUDE_IPERF3=y
CONFIG_FIRMWARE_INCLUDE_DUMP1090=n
CONFIG_FIRMWARE_INCLUDE_RTL_SDR=n
CONFIG_FIRMWARE_INCLUDE_MTR=y
CONFIG_FIRMWARE_INCLUDE_SOCAT=n
CONFIG_FIRMWARE_INCLUDE_SRELAY=n
CONFIG_FIRMWARE_INCLUDE_MENTOHUST=n
CONFIG_FIRMWARE_INCLUDE_FRPC=n
CONFIG_FIRMWARE_INCLUDE_FRPS=n
CONFIG_FIRMWARE_INCLUDE_WIREGUARD=y
CONFIG_FIRMWARE_INCLUDE_ZEROTIER=n
CONFIG_FIRMWARE_INCLUDE_ALIDDNS=n
CONFIG_FIRMWARE_INCLUDE_DDNSTO=n
CONFIG_FIRMWARE_INCLUDE_TAILSCALE=y
CONFIG_FIRMWARE_INCLUDE_ADGUARDHOME=y
CONFIG_FIRMWARE_INCLUDE_NATPIERCE=n
CONFIG_FIRMWARE_INCLUDE_VNTCLI=n
CONFIG_FIRMWARE_INCLUDE_VNTS=n
CONFIG_FIRMWARE_INCLUDE_CLOUDFLARED=n
CONFIG_FIRMWARE_INCLUDE_LUCKY=n
CONFIG_FIRMWARE_INCLUDE_CLOUDFLARE=n
CONFIG_FIRMWARE_INCLUDE_EASYTIER=n
CONFIG_FIRMWARE_INCLUDE_ALIST=n
CONFIG_FIRMWARE_INCLUDE_WXSEND=n
CONFIG_FIRMWARE_INCLUDE_UUPLUGIN=n
CONFIG_FIRMWARE_INCLUDE_ALDRIVER=n
CONFIG_FIRMWARE_INCLUDE_VIRTUALHERE=n
CONFIG_FIRMWARE_INCLUDE_WYY=n
CONFIG_FIRMWARE_INCLUDE_BAFA=n
CONFIG_FIRMWARE_INCLUDE_CADDY=y
CONFIG_FIRMWARE_INCLUDE_SMARTDNS=n
CONFIG_FIRMWARE_INCLUDE_NETCAT=y
CONFIG_FIRMWARE_INCLUDE_MSD_LITE=n
CONFIG_FIRMWARE_INCLUDE_SINGBOX=y
CONFIG_FIRMWARE_INCLUDE_CAKE=y
CONFEOF

echo ">>> HOÀN TẤT CHUẨN BỊ SOURCE VÀ CẤU HÌNH!"