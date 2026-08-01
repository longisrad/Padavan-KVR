SRC_NAME = Tailscale
THISDIR = $(shell pwd)

all:

extract_test:

config_test:
clean:

romfs:
	$(ROMFSINST) $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
	@if [ -f $(THISDIR)/tailscaled.bin ]; then \
		$(ROMFSINST) -p +x $(THISDIR)/tailscaled.bin /etc/tailscaled.bin ; \
	fi
