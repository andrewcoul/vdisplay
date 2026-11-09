PREFIX ?= $(HOME)/.local
CFLAGS ?= -O2 -Wall
FRAMEWORKS = -framework Foundation -framework CoreGraphics -framework IOKit

vdisplay: vdisplay.m
	clang -fobjc-arc $(CFLAGS) $(FRAMEWORKS) $< -o $@

install: vdisplay
	install -d $(PREFIX)/bin
	install -m 755 vdisplay $(PREFIX)/bin/vdisplay

uninstall:
	rm -f $(PREFIX)/bin/vdisplay

clean:
	rm -f vdisplay

.PHONY: install uninstall clean
