THISDIR = $(shell pwd)
all:

clean:

romfs:
	# 1. Copy script quản lý chính vào /usr/bin/
	$(ROMFSINST) -p +x $(THISDIR)/singbox.sh /usr/bin/singbox.sh

	# 2. Copy các helper script và template vào /etc_ro/singbox/
	mkdir -p $(ROMFSDIR)/etc_ro/singbox
	$(ROMFSINST) $(THISDIR)/converter.lua /etc_ro/singbox/converter.lua
	$(ROMFSINST) -p +x $(THISDIR)/gen_links.sh /etc_ro/singbox/gen_links.sh
	$(ROMFSINST) -p +x $(THISDIR)/sub_mgr.sh /etc_ro/singbox/sub_mgr.sh
    $(ROMFSINST) -p +x $(THISDIR)/singbox_route.sh /etc_ro/singbox/singbox_route.sh
