KERNEL_VERSION = linux-6.2.9
KERNEL_REMOTE = https://cdn.kernel.org/pub/linux/kernel/v6.x/$(KERNEL_VERSION).tar.xz
KERNEL_TARBALL = tarballs/$(KERNEL_VERSION).tar.xz
KERNEL_SOURCES = $(KERNEL_VERSION)
KERNEL_PATCHES = $(shell find patches/ -name "0*.patch" | sort)
KERNEL_C_BUNDLE = kernel.c

ABI_VERSION = 3
FULL_VERSION = 3.11.0
TIMESTAMP = "Mon Apr  3 04:28:59 PM CEST 2023"

KERNEL_FLAGS = KBUILD_BUILD_TIMESTAMP=$(TIMESTAMP)
KERNEL_FLAGS += KBUILD_BUILD_USER=root
KERNEL_FLAGS += KBUILD_BUILD_HOST=libkrunfw

ifeq ($(SEV),1)
    VARIANT = -sev
    KERNEL_PATCHES += $(shell find patches-sev/ -name "0*.patch" | sort)
endif

ARCH = $(shell uname -m)
OS = $(shell uname -s)

KBUNDLE_TYPE_x86_64 = vmlinux
KBUNDLE_TYPE_aarch64 = Image

KERNEL_BINARY_x86_64 = $(KERNEL_SOURCES)/vmlinux
KERNEL_BINARY_aarch64 = $(KERNEL_SOURCES)/arch/arm64/boot/Image

KRUNFW_BINARY_Linux = libkrunfw$(VARIANT).so.$(FULL_VERSION)
KRUNFW_SONAME_Linux = libkrunfw$(VARIANT).so.$(ABI_VERSION)
KRUNFW_BASE_Linux = libkrunfw$(VARIANT).so
SONAME_Linux = -Wl,-soname,$(KRUNFW_SONAME_Linux)

KRUNFW_BINARY_Darwin = libkrunfw.$(ABI_VERSION).dylib
KRUNFW_SONAME_Darwin = libkrunfw.$(ABI_VERSION).dylib
KRUNFW_BASE_Darwin = libkrunfw.dylib
SONAME_Darwin =

LIBDIR_Linux = lib64
LIBDIR_Darwin = lib

ifeq ($(PREFIX),)
    PREFIX := /usr/local
endif

ifeq ($(SEV),1)
    QBOOT_BINARY = qboot/bios.bin
    QBOOT_C_BUNDLE = qboot.c
    INITRD_BINARY = initrd/initrd.gz
    INITRD_C_BUNDLE = initrd.c
endif

.PHONY: all install clean

all: $(KRUNFW_BINARY_$(OS))

$(KERNEL_TARBALL):
	@mkdir -p tarballs
	curl $(KERNEL_REMOTE) -o $(KERNEL_TARBALL)

$(KERNEL_SOURCES): $(KERNEL_TARBALL)
	tar xf $(KERNEL_TARBALL)
	for patch in $(KERNEL_PATCHES); do patch -p1 -d $(KERNEL_SOURCES) < "$$patch"; done
	cp config-libkrunfw$(VARIANT)_$(ARCH) $(KERNEL_SOURCES)/.config
	cd $(KERNEL_SOURCES) ; $(MAKE) olddefconfig

$(KERNEL_BINARY_$(ARCH)): $(KERNEL_SOURCES)
	cd $(KERNEL_SOURCES) ; rm -f .version ; $(MAKE) $(MAKEFLAGS) $(KERNEL_FLAGS)

ifeq ($(OS),Darwin)
$(KERNEL_C_BUNDLE):
	@echo "Building on macOS, using ./build_on_krunvm.sh"
	./build_on_krunvm.sh
else
$(KERNEL_C_BUNDLE): $(KERNEL_BINARY_$(ARCH))
	@echo "Generating $(KERNEL_C_BUNDLE) from $(KERNEL_BINARY_$(ARCH))..."
	@python3 bin2cbundle.py -t $(KBUNDLE_TYPE_$(ARCH)) $(KERNEL_BINARY_$(ARCH)) kernel.c
endif

ifeq ($(SEV),1)
$(QBOOT_C_BUNDLE): $(QBOOT_BINARY)
	@echo "Generating $(QBOOT_C_BUNDLE) from $(QBOOT_BINARY)..."
	@python3 bin2cbundle.py -t qboot $(QBOOT_BINARY) qboot.c

$(INITRD_C_BUNDLE): $(INITRD_BINARY)
	@echo "Generating $(INITRD_C_BUNDLE) from $(INITRD_BINARY)..."
	@python3 bin2cbundle.py -t initrd $(INITRD_BINARY) initrd.c
endif

$(KRUNFW_BINARY_$(OS)): $(KERNEL_C_BUNDLE) $(QBOOT_C_BUNDLE) $(INITRD_C_BUNDLE)
	gcc -fPIC -DABI_VERSION=$(ABI_VERSION) -shared $(SONAME_$(OS)) -o $@ $(KERNEL_C_BUNDLE) $(QBOOT_C_BUNDLE) $(INITRD_C_BUNDLE)
ifeq ($(OS),Linux)
	strip $(KRUNFW_BINARY_$(OS))
endif

install:
	install -d $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/
	install -m 755 $(KRUNFW_BINARY_$(OS)) $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/
ifeq ($(OS),Darwin)
	cd $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/ ; ln -sf $(KRUNFW_BINARY_$(OS)) $(KRUNFW_BASE_$(OS))
else
	cd $(DESTDIR)$(PREFIX)/$(LIBDIR_$(OS))/ ; ln -sf $(KRUNFW_BINARY_$(OS)) $(KRUNFW_SONAME_$(OS)) ; ln -sf $(KRUNFW_SONAME_$(OS)) $(KRUNFW_BASE_$(OS))
endif

clean:
	rm -fr $(KERNEL_SOURCES) $(KERNEL_C_BUNDLE) $(QBOOT_C_BUNDLE) $(INITRD_C_BUNDLE) $(KRUNFW_BINARY_$(OS))
