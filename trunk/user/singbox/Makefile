THISDIR = $(shell pwd)
all:

clean:

romfs:
	# 1. Copy file quản lý chính vào /usr/bin/
	$(ROMFSINST) -p +x $(THISDIR)/singbox.sh /usr/bin/singbox.sh
	
	# 2. Copy bộ template & parser nhẹ (~10KB) vào /etc_ro/
	mkdir -p $(ROMFSDIR)/etc_ro/singbox
	[ -f $(THISDIR)/converter.lua ] && $(ROMFSINST) $(THISDIR)/converter.lua /etc_ro/singbox/converter.lua
	[ -f $(THISDIR)/conf3_final.json ] && $(ROMFSINST) $(THISDIR)/conf3_final.json /etc_ro/singbox/conf3_final.json
