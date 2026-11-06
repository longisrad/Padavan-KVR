#!/usr/bin/env python3
"""Vá backend CAKE SQM vào source Padavan (rc / httpd / shared).
Dùng: python3 patch_cake_backend.py /opt/rt-n56u/trunk
- Tự tìm file theo tên + nội dung, báo lỗi rõ nếu không thấy/mơ hồ.
- Chạy lại nhiều lần an toàn (đã vá thì bỏ qua).
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
        print("bỏ qua (đã vá):", path)
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
    s = insert_after_line(s, r"^#define EVM_RESTART_ZEROTIER.*$",
        "#if defined(APP_ZEROTIER)\n"
        "#error \"CAKE reuses the ZeroTier event bit (1ULL << 51)\"\n"
        "#endif\n"
        "#define EVM_RESTART_CAKE\t\t\t(1ULL << 51) //CAKE SQM (reuses ZeroTier bit, ZeroTier disabled)")
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

# ---- rc.c -------------------------------------------------------------
RC_BRANCH = '''\t\telse if (strcmp(entry->d_name, RCN_RESTART_CAKE) == 0)
\t\t{
\t\t\trestart_cake();
\t\t}
'''
edit(find("rc.c", "RCN_RESTART_SINGBOX"), "RCN_RESTART_CAKE",
     lambda s: insert_before(s, "#if defined(APP_SINGBOX)\n\t\telse if (strcmp(entry->d_name, RCN_RESTART_SINGBOX) == 0)", RC_BRANCH))

# ---- variables.c ------------------------------------------------------
CAKE_KEYS = ["cake_enable","cake_down_bw","cake_up_bw","cake_flow_mode","cake_diffserv",
             "cake_rtt","cake_overhead","cake_ack_filter","cake_nat","cake_wash"]
def p_vars(s):
    body = "".join('\t\t\t{"%s", "", NULL, EVM_RESTART_CAKE},\n' % k for k in CAKE_KEYS)
    body += '\t\t\t{"cake_custom", "64", NULL, EVM_RESTART_CAKE},\n'
    struct = "    struct variable variables_CakeConf[] = {\n" + body + "\t\t\t{0,0,0,0}\n\t};\n\n"
    s = insert_before(s, "#if defined(APP_SINGBOX)\n    struct variable variables_SingboxConf[] = {", struct)
    s = insert_before(s, "#if defined(APP_SINGBOX)\n\t\t{\"SingboxConf\",\t\tvariables_SingboxConf},",
                      "\t\t{\"CakeConf\",\t\tvariables_CakeConf},\n")
    s = insert_before(s, "#if defined(APP_SINGBOX)\n\t\t{EVM_RESTART_SINGBOX,",
                      "\t\t{EVM_RESTART_CAKE,\t\tEVT_RESTART_CAKE,\t\tRCN_RESTART_CAKE,\t0},\n")
    return s
edit(find("variables.c", "variables_SingboxConf"), "variables_CakeConf", p_vars)

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
\t{ "cake_custom", "" },'''
def p_def(s):
    if '"w_singbox"' not in s:
        s = insert_after_line(s, r'^\t\{ "w_v2raya", "1" \},$', '\t{ "w_singbox", "1" },')
    return insert_after_line(s, r'^\t\{ "w_v2raya", "1" \},$', DEFAULTS)
edit(find("defaults.c", '"w_v2raya"'), '"w_cake"', p_def)

# ---- web_ex.c ---------------------------------------------------------
WEB = '''\telse if (!strcmp(value, " GetCakeStatus "))
\t{
\t\tsystem("/usr/bin/cake.sh status > /tmp/cake_status.txt 2>&1");
\t\tdump_file(wp, "/tmp/cake_status.txt");
\t\treturn 0;
\t}
'''
edit(find("web_ex.c", " GetSingboxClients "), "GetCakeStatus",
     lambda s: insert_before(s, '\telse if (!strcmp(value, " CheckSingboxSubUrl "))', WEB))

print("XONG: backend CAKE đã vá.")
