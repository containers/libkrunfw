KERNEL_VERSION = linux-5.10.10
KERNEL_REMOTE = https://cdn.kernel.org/pub/linux/kernel/v5.x/$(KERNEL_VERSION).tar.xz
KERNEL_TARBALL = tarballs/$(KERNEL_VERSION).tar.xz
KERNEL_SOURCES = $(KERNEL_VERSION)
KERNEL_PATCHES = $(shell find patches/ -name "0*.patch" | sort)
KERNEL_C_BUNDLE = kernel.c

ARCH = $(shell uname -m)
BUNDLE_SCRIPT_x86_64 = vmlinux_to_bundle.py
BUNDLE_SCRIPT_aarch64 = Image_to_bundle.py
KERNEL_BINARY_x86_64 = $(KERNEL_SOURCES)/vmlinux
KERNEL_BINARY_aarch64 = $(KERNEL_SOURCES)/arch/arm64/boot/Image

ifeq ($(PREFIX),)
    PREFIX := /usr/local
endif

.PHONY: all install clean

all: libkrunfw.so

$(KERNEL_TARBALL):
	@mkdir -p tarballs
	curl $(KERNEL_REMOTE) -o $(KERNEL_TARBALL)

$(KERNEL_SOURCES): $(KERNEL_TARBALL)
	tar xf $(KERNEL_TARBALL)
	for patch in $(KERNEL_PATCHES); do patch -p1 -d $(KERNEL_SOURCES) < "$$patch"; done
	cp config-libkrunfw_$(ARCH) $(KERNEL_SOURCES)/.config
	cd $(KERNEL_SOURCES) ; $(MAKE) oldconfig

$(KERNEL_BINARY_$(ARCH)): $(KERNEL_SOURCES)
	cd $(KERNEL_SOURCES) ; $(MAKE) $(MAKEFLAGS)

$(KERNEL_C_BUNDLE): $(KERNEL_BINARY_$(ARCH))
	@echo "Generating $(KERNEL_C_BUNDLE) from $(KERNEL_BINARY_$(ARCH))..."
	@python3 $(BUNDLE_SCRIPT_$(ARCH)) $(KERNEL_BINARY_$(ARCH))

libkrunfw.so: $(KERNEL_C_BUNDLE)
	gcc -fPIC -shared -o $@ $(KERNEL_C_BUNDLE)

install: libkrunfw.so
	install -d $(DESTDIR)$(PREFIX)/lib64/
	install -m 755 libkrunfw.so $(DESTDIR)$(PREFIX)/lib64/

clean:
	rm -fr $(KERNEL_SOURCES) $(KERNEL_C_BUNDLE) libkrunfw.so
