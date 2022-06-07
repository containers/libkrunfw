from elftools.elf.elffile import ELFFile
import sys

footer = """
char * krunfw_get_initrd(size_t *size)
{
    *size = INITRD_SIZE;
    return &INITRD_BUNDLE[0];
}
"""

load_segments = [ ]

if len(sys.argv) != 2:
    print('Invalid arguments')
    print('Usage: %s INITRD_BINARY' % sys.argv[0])
    sys.exit(-1)

initrd = open(sys.argv[1], 'rb')

qc = open('initrd.c', 'w')
qc.write('#include <stddef.h>\n')
qc.write('__attribute__ ((aligned (4096))) char INITRD_BUNDLE[] = \n"')

col = 0
pos = 0
prev_paddr = None
byte = initrd.read(1)
while byte:
    qc.write('\\x' + format(byte[0], 'x'))
    if col == 20:
        qc.write('"\n"')
        col = 0
    else:
        col = col + 1

    pos = pos + 1
    byte = initrd.read(1)

qc.write('";\n')
qc.write('size_t INITRD_SIZE = 0x%s;\n' % format(pos, 'x'))
qc.write(footer)
