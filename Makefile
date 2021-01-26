KERNEL_VERSION = linux-5.10.10
KERNEL_REMOTE = https://cdn.kernel.org/pub/linux/kernel/v5.x/$(KERNEL_VERSION).tar.xz
KERNEL_TARBALL = tarballs/$(KERNEL_VERSION).tar.xz
KERNEL_SOURCES = $(KERNEL_VERSION)
KERNEL_BINARY = $(KERNEL_SOURCES)/vmlinux
KERNEL_PATCHES = $(shell find patches/ -name "0*.patch" | sort)
KERNEL_C_BUNDLE = kernel.c

ifeq ($(PREFIX),)
    PREFIX := /usr/local
endif

.PHONY: all install clean

all: libkrunfw.so

$(KERNEL_TARBALL):
	@mkdir -p tarballs
	wget $(KERNEL_REMOTE) -O $(KERNEL_TARBALL)

$(KERNEL_SOURCES): $(KERNEL_TARBALL)
	tar xf $(KERNEL_TARBALL)
	for patch in $(KERNEL_PATCHES); do patch -p1 -d $(KERNEL_SOURCES) < "$$patch"; done
	cp config-libkrunfw $(KERNEL_SOURCES)/.config
	cd $(KERNEL_SOURCES) ; $(MAKE) oldconfig

$(KERNEL_BINARY): $(KERNEL_SOURCES)
	cd $(KERNEL_SOURCES) ; $(MAKE) $(MAKEFLAGS)

$(KERNEL_C_BUNDLE): $(KERNEL_BINARY)
	@echo "Generating $(KERNEL_C_BUNDLE) from $(KERNEL_BINARY)..."
	@python3 vmlinux_to_bundle.py $(KERNEL_BINARY)

libkrunfw.so: $(KERNEL_C_BUNDLE)
	gcc -fPIC -shared -o $@ $(KERNEL_C_BUNDLE)

install: libkrunfw.so
	install -d $(DESTDIR)$(PREFIX)/lib64/
	install -m 755 libkrunfw.so $(DESTDIR)$(PREFIX)/lib64/

clean:
	rm -fr $(KERNEL_SOURCES) $(KERNEL_C_BUNDLE) libkrunfw.so
