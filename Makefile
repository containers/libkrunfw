KERNEL_VERSION = linux-5.15.43
KERNEL_REMOTE = https://cdn.kernel.org/pub/linux/kernel/v5.x/$(KERNEL_VERSION).tar.xz
KERNEL_TARBALL = tarballs/$(KERNEL_VERSION).tar.xz
KERNEL_SOURCES = $(KERNEL_VERSION)
KERNEL_PATCHES = $(shell find patches/ -name "0*.patch" | sort)
KERNEL_C_BUNDLE = kernel.c

ARCH = $(shell uname -m)
OS = $(shell uname -s)
BUNDLE_SCRIPT_x86_64 = vmlinux_to_bundle.py
BUNDLE_SCRIPT_aarch64 = Image_to_bundle.py
KERNEL_BINARY_x86_64 = $(KERNEL_SOURCES)/vmlinux
KERNEL_BINARY_aarch64 = $(KERNEL_SOURCES)/arch/arm64/boot/Image
KRUNFW_BINARY_Linux = libkrunfw.so
KRUNFW_BINARY_Darwin = libkrunfw.dylib
LIBDIR_Linux = lib64
LIBDIR_Darwin = lib

ifeq ($(PREFIX),)
    PREFIX := /usr/local
endif

.PHONY: all install clean

all: $(KRUNFW_BINARY_$(OS))

$(KERNEL_TARBALL):
	@mkdir -p tarballs
	curl $(KERNEL_REMOTE) -o $(KERNEL_TARBALL)

$(KERNEL_SOURCES): $(KERNEL_TARBALL)
	tar xf $(KERNEL_TARBALL)
	for patch in $(KERNEL_PATCHES); do patch -p1 -d $(KERNEL_SOURCES) < "$$patch"; done
	cp config-libkrunfw_$(ARCH) $(KERNEL_SOURCES)/.config
	cd $(KERNEL_SOURCES) ; $(MAKE) olddefconfig

$(KERNEL_BINARY_$(ARCH)): $(KERNEL_SOURCES)
	cd $(KERNEL_SOURCES) ; $(MAKE) $(MAKEFLAGS)

$(KERNEL_C_BUNDLE): $(KERNEL_BINARY_$(ARCH))
	@echo "Generating $(KERNEL_C_BUNDLE) from $(KERNEL_BINARY_$(ARCH))..."
	@python3 $(BUNDLE_SCRIPT_$(ARCH)) $(KERNEL_BINARY_$(ARCH))

$(KRUNFW_BINARY_$(OS)): $(KERNEL_C_BUNDLE)
	gcc -fPIC -shared -o $@ $(KERNEL_C_BUNDLE)

install: $(KRUNFW_BINARY_$(OS))
	install -d $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/
	install -m 755 $(KRUNFW_BINARY_$(OS)) $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/

clean:
	rm -fr $(KERNEL_SOURCES) $(KERNEL_C_BUNDLE) $(KRUNFW_BINARY_$(OS))
