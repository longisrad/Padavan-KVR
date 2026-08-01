THISDIR = $(shell pwd)
all:

clean:

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/adguardhome.sh /usr/bin/adguardhome.sh
	@if [ -f $(THISDIR)/AdGuardHome.bin ]; then \
		$(ROMFSINST) -p +x $(THISDIR)/AdGuardHome.bin /etc/AdGuardHome.bin ; \
	fi
