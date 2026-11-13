#!/usr/bin/env python3
"""Vá backend CAKE SQM vào source Padavan (rc / httpd / shared).
Dùng: python3 patch_cake_backend.py /opt/rt-n56u/trunk
- Tự tìm file theo tên + nội dung, báo lỗi rõ nếu không thấy/mơ hồ.
- Chạy lại nhiều lần an toàn (đã vá đầy đủ thì bỏ qua, thiếu biến mới thì tự nâng cấp).
"""
import os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/opt/rt-n56u/trunk"

def find(name, needle):
    hits = []
    for d, _, files in os.walk(ROOT):
        if "/romfs" in d or "/stage" in d or "/.git" in d:
            continue
        if name in files:
            p = os.path.join(d, name)
            try:
                if needle in open(p, encoding="utf-8", errors="replace").read():
                    hits.append(p)
            except OSError:
                pass
    if len(hits) != 1:
        sys.exit("LỖI: tìm %s chứa %r được %d file: %s" % (name, needle, len(hits), hits))
    return hits[0]

def edit(path, marker, fn):
    s = open(path, encoding="utf-8", errors="surrogateescape").read()
    if marker in s:
        print("bỏ qua (đã có %s): %s" % (marker, path))
        return
    s2 = fn(s)
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(s2)
    print("đã vá:", path)

def insert_before(s, anchor, text):
    if s.count(anchor) != 1:
        sys.exit("LỖI: anchor xuất hiện %d lần: %r" % (s.count(anchor), anchor[:60]))
    return s.replace(anchor, text + anchor)

def insert_after_line(s, regex, text):
    m = list(re.finditer(regex, s, re.M))
    if len(m) != 1:
        sys.exit("LỖI: regex %r khớp %d lần" % (regex, len(m)))
    e = m[0].end()
    return s[:e] + "\n" + text.rstrip("\n") + s[e:]

# ---- common.h ---------------------------------------------------------
def p_common(s):
    s = insert_after_line(s, r"^#define EVM_RESTART_SWITCH_VLAN.*$",
        "#define EVM_RESTART_CAKE\t\t\t(1ULL << 16) //CAKE SQM")
    s = insert_after_line(s, r"^#define EVT_RESTART_SINGBOX.*$", "#define EVT_RESTART_CAKE\t\t2")
    return s
edit(find("common.h", "EVM_RESTART_SINGBOX"), "EVM_RESTART_CAKE", p_common)

# ---- notify_rc.h ------------------------------------------------------
edit(find("notify_rc.h", "RCN_RESTART_SINGBOX"), "RCN_RESTART_CAKE",
     lambda s: insert_after_line(s, r"^#define RCN_RESTART_SINGBOX.*$",
                                 "#define RCN_RESTART_CAKE\t\t\"restart_cake\""))

# ---- rc.h -------------------------------------------------------------
def p_rch(s):
    a = "void update_singbox_sub(void);\n#endif\n"
    if s.count(a) != 1:
        sys.exit("LỖI: rc.h anchor update_singbox_sub")
    return s.replace(a, a + "void stop_cake(void);\nvoid start_cake(void);\nvoid restart_cake(void);\n")
edit(find("rc.h", "restart_singbox"), "restart_cake", p_rch)

# ---- services.c -------------------------------------------------------
CAKE_FUNCS = '''void stop_cake(void){
\teval("/usr/bin/cake.sh","stop");
}

void start_cake(void){
\tif (nvram_get_int("cake_enable") == 1)
\t\teval("/usr/bin/cake.sh","start");
}

void restart_cake(void){
\teval("/usr/bin/cake.sh","restart");
}

'''
edit(find("services.c", "start_singbox"), "restart_cake",
     lambda s: insert_before(s, "#if defined(APP_SINGBOX)\nvoid stop_singbox(void){", CAKE_FUNCS))

# khởi động CAKE khi boot
edit(find("services.c", "start_singbox"), "CAKE_BOOT_HOOK",
     lambda s: insert_before(s, '\tsystem("/usr/bin/iappd.sh start");\n\treturn 0;\n',
                             '\t/* CAKE_BOOT_HOOK */\n\tstart_cake();\n'))

# ---- rc.c -------------------------------------------------------------
RC_BRANCH = '''\t\telse if (strcmp(entry->d_name, RCN_RESTART_CAKE) == 0)
\t\t{
\t\t\trestart_cake();
\t\t}
'''
edit(find("rc.c", "RCN_RESTART_SINGBOX"), "RCN_RESTART_CAKE",
     lambda s: insert_before(s, "#if defined(APP_SINGBOX)\n\t\telse if (strcmp(entry->d_name, RCN_RESTART_SINGBOX) == 0)", RC_BRANCH))

# ---- variables.c ------------------------------------------------------
# Khóa đăng ký cho trang web (khóa không có ở đây thì httpd bỏ qua khi bấm Apply)
CAKE_KEYS = ["cake_enable","cake_down_bw","cake_up_bw","cake_flow_mode","cake_diffserv",
             "cake_rtt","cake_overhead","cake_ack_filter","cake_nat","cake_wash",
             "cake_dscp_auto","cake_dscp_small_udp","cake_fb_qdisc"]
NEWEST_KEY = "cake_fb_qdisc"   # dấu hiệu "đã vá đủ"; thiếu thì tự nâng cấp
def p_vars(s):
    body = "".join('\t\t\t{"%s", "", NULL, EVM_RESTART_CAKE},\n' % k for k in CAKE_KEYS)
    body += '\t\t\t{"cake_custom", "64", NULL, EVM_RESTART_CAKE},\n'
    struct = "    struct variable variables_CakeConf[] = {\n" + body + "\t\t\t{0,0,0,0}\n\t};\n\n"
    
    # Đã vá bản cũ (thiếu khóa mới) -> thay thế nguyên struct
    if "variables_CakeConf" in s:
        s, n = re.subn(r'    struct variable variables_CakeConf\[\] = \{[\s\S]*?\};\n\n', lambda m: struct, s)
        if n != 1:
            sys.exit("LỖI: không tìm thấy struct variables_CakeConf để nâng cấp (n=%d)" % n)
        return s

    s = insert_before(s, "#if defined(APP_SINGBOX)\n    struct variable variables_SingboxConf[] = {", struct)
    s = insert_before(s, "#if defined(APP_SINGBOX)\n\t\t{\"SingboxConf\",\t\tvariables_SingboxConf},",
                      "\t\t{\"CakeConf\",\t\tvariables_CakeConf},\n")
    s = insert_before(s, "#if defined(APP_SINGBOX)\n\t\t{EVM_RESTART_SINGBOX,",
                      "\t\t{EVM_RESTART_CAKE,\t\tEVT_RESTART_CAKE,\t\tRCN_RESTART_CAKE,\t0},\n")
    return s
edit(find("variables.c", "variables_SingboxConf"), NEWEST_KEY, p_vars)

# ---- defaults.c -------------------------------------------------------
DEFAULTS = '''\t{ "w_cake", "1" },
\t{ "cake_enable", "0" },
\t{ "cake_down_bw", "0" },
\t{ "cake_up_bw", "0" },
\t{ "cake_flow_mode", "auto" },
\t{ "cake_diffserv", "diffserv3" },
\t{ "cake_rtt", "internet" },
\t{ "cake_overhead", "ethernet" },
\t{ "cake_ack_filter", "none" },
\t{ "cake_nat", "1" },
\t{ "cake_wash", "0" },
\t{ "cake_dscp_auto", "0" },
\t{ "cake_dscp_small_udp", "0" },
\t{ "cake_fb_qdisc", "auto" },
\t{ "cake_custom", "" },'''

def p_def(s):
    # Đã vá bản cũ (thiếu khóa mới) -> thay khối từ w_cake đến cake_custom
    if '"w_cake"' in s:
        s, n = re.subn(r'\t\{ "w_cake", "1" \},[\s\S]*?\t\{ "cake_custom", "" \},', lambda m: DEFAULTS, s)
        if n != 1:
            sys.exit("LỖI: không tìm thấy khối defaults w_cake..cake_custom để nâng cấp (n=%d)" % n)
        return s

    if '"w_singbox"' not in s:
        s = insert_after_line(s, r'^\t\{ "w_v2raya", "1" \},$', '\t{ "w_singbox", "1" },')
    return insert_after_line(s, r'^\t\{ "w_v2raya", "1" \},$', DEFAULTS)
edit(find("defaults.c", '"w_v2raya"'), NEWEST_KEY, p_def)

# ---- web_ex.c ---------------------------------------------------------
WEB_TOOLS = '''\telse if (!strcmp(value, " CakeToolRun "))
\t{
\t\tchar *tool = websGetVar(wp, "cake_tool", "");
\t\tif (!strcmp(tool, "status") || !strcmp(tool, "check") ||
\t\t    !strcmp(tool, "test") || !strcmp(tool, "restart"))
\t\t{
\t\t\tchar cmd[192];
\t\t\tunlink("/tmp/cake_tool.txt");
\t\t\tsnprintf(cmd, sizeof(cmd),
\t\t\t\t"(/usr/bin/cake.sh %s > /tmp/cake_tool.txt 2>&1; echo '[xong]' >> /tmp/cake_tool.txt) &", tool);
\t\t\tsystem(cmd);
\t\t}
\t\treturn 0;
\t}
\telse if (!strcmp(value, " GetCakeToolOutput "))
\t{
\t\tdump_file(wp, "/tmp/cake_tool.txt");
\t\treturn 0;
\t}
'''
WEB_STATUS = '''\telse if (!strcmp(value, " GetCakeStatus "))
\t{
\t\tsystem("/usr/bin/cake.sh status > /tmp/cake_status.txt 2>&1");
\t\tdump_file(wp, "/tmp/cake_status.txt");
\t\treturn 0;
\t}
'''
WEB_FILE = find("web_ex.c", " GetSingboxClients ")
edit(WEB_FILE, "GetCakeStatus",
     lambda s: insert_before(s, '\telse if (!strcmp(value, " CheckSingboxSubUrl "))', WEB_TOOLS + WEB_STATUS))
edit(WEB_FILE, "CakeToolRun",
     lambda s: insert_before(s, '\telse if (!strcmp(value, " GetCakeStatus "))', WEB_TOOLS))

print("XONG: backend CAKE đã vá đầy đủ.")
