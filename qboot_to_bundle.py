from elftools.elf.elffile import ELFFile
import sys

footer = """
char * krunfw_get_qboot(size_t *size)
{
    *size = QBOOT_SIZE;
    return &QBOOT_BUNDLE[0];
}
"""

load_segments = [ ]    

if len(sys.argv) != 2:
    print('Invalid arguments')
    print('Usage: %s QBOOT_BINARY' % sys.argv[0])
    sys.exit(-1)

qboot = open(sys.argv[1], 'rb')

qc = open('qboot.c', 'w')
qc.write('#include <stddef.h>\n')
qc.write('__attribute__ ((aligned (4096))) char QBOOT_BUNDLE[] = \n"')

col = 0
pos = 0
prev_paddr = None
byte = qboot.read(1)
while byte:
    qc.write('\\x' + format(byte[0], 'x'))
    if col == 20:
        qc.write('"\n"')
        col = 0
    else:
        col = col + 1

    pos = pos + 1
    byte = qboot.read(1)
        
qc.write('";\n')
qc.write('size_t QBOOT_SIZE = 0x%s;\n' % format(pos, 'x'))
qc.write(footer)
