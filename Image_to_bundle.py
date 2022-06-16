import sys

footer = """
char * krunfw_get_kernel(size_t *load_addr, size_t *size)
{
    *load_addr = KERNEL_LOAD_ADDR;
    *size = (((KERNEL_SIZE - 1) / 16384) + 1) * 16384;
    return &KERNEL_BUNDLE[0];
}

int krunfw_get_version()
{
    return ABI_VERSION;
}
"""

load_segments = [ ]

if len(sys.argv) != 2:
    print('Invalid arguments')
    print('Usage: %s VMLINUX_BINARY' % sys.argv[0])
    sys.exit(-1)

kelf = open(sys.argv[1], 'rb')

kc = open('kernel.c', 'w')
kc.write('#include <stddef.h>\n')
kc.write('__attribute__ ((aligned (4096))) char KERNEL_BUNDLE[] = \n"')

entry = 0x80000000;
col = 0
pos = 0
prev_paddr = None
byte = kelf.read(1)
while byte != b"":
    kc.write('\\x' + byte.hex())
    if col == 20:
        kc.write('"\n"')
        col = 0
    else:
        col = col + 1
    byte = kelf.read(1)
    pos = pos + 1

kc.write('";\n')
kc.write('size_t KERNEL_SIZE = 0x%s;\n' % format(pos, 'x'))
kc.write('size_t KERNEL_LOAD_ADDR = 0x%s;\n' % format(entry, 'x'))
kc.write(footer)
