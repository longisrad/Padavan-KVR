THISDIR = $(shell pwd)
all:

clean:

romfs:
	$(ROMFSINST) -p +x $(THISDIR)/adguardhome.sh /usr/bin/adguardhome.sh
	@if [ -f $(THISDIR)/AdGuardHome.tar.gz ]; then \
		$(ROMFSINST) $(THISDIR)/AdGuardHome.tar.gz /etc/AdGuardHome.tar.gz ; \
	fi
