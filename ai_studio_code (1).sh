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

# 1. Quét và vá RCN_RESTART_CAKE vào TẤT CẢ các file notify_rc.h trong source
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

# 5. variables.c - ĐẶT variables_CakeConf RA NGOÀI (ngay trước svcLinks[]) ĐỂ TRÁNH BỊ #if defined CỦA APP KHÁC NUỐT MẤT
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

# Chèn variables_CakeConf ngay trước bảng svcLinks (độc lập, không bị phụ thuộc vào app nào)
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

print("=== HOÀN TẤT VÁ SỬA LỖI TẦNG C CHO CAKE ===")
EOF