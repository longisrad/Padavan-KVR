#!/bin/sh
### Custom user script
### Called after internal iptables reconfig (firewall update)
#wing resume
#自动配置 POSTROUTING 的 MSS钳制,防止网络堵塞和数据丢失
iptables -t mangle -A POSTROUTING ! -o br0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ip6tables -t mangle -A POSTROUTING ! -o br0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
# 手动指定MSS
#iptables -t mangle -A POSTROUTING ! -o br0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
#ip6tables -t mangle -A POSTROUTING ! -o br0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1432
### ipv6防火墙全关规则 以下把#去掉则关闭ip6防火墙
#ip6tables -F
#ip6tables -X
#ip6tables -P INPUT ACCEPT
#ip6tables -P OUTPUT ACCEPT
#ip6tables -P FORWARD ACCEPT
### ipv6防火墙单独规则 开放3389远程桌面 其它端口按下方规则添加 以下把#去掉则生效
#ip6tables -I FORWARD -p tcp --dport 3389 -j ACCEPT
#ip6tables -I FORWARD -p tcp --dport 8829 -j ACCEPT

### sing-box: reapply TPROXY chain sau khi Padavan flush/rebuild iptables noi
### bo (WAN reconnect, Apply settings...). Neu khong co dong nay, chain
### SINGBOX se bi mat sau moi lan reconnect WAN, gay mat mang toan bo LAN
### du sing-box van dang chay binh thuong (bug da tung gap va debug ky).
[ -x /usr/bin/singbox.sh ] && /usr/bin/singbox.sh reapply_iptables
