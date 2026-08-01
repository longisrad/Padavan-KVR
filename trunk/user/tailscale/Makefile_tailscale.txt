SRC_NAME = Tailscale
THISDIR = $(shell pwd)

all:

extract_test:

config_test:
clean:

romfs:
	$(ROMFSINST) $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
	@if [ -f $(THISDIR)/tailscaled.gz ]; then \
		$(ROMFSINST) $(THISDIR)/tailscaled.gz /etc/tailscaled.gz ; \
	fi
