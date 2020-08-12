from elftools.elf.elffile import ELFFile
import sys

footer = """
char * get_kernel_bundle(size_t *load_addr, size_t *size)
{
    *load_addr = KERNEL_LOAD_ADDR;
    *size = KERNEL_SIZE;
    return &KERNEL_BUNDLE[0];
}
"""

load_segments = [ ]    

if len(sys.argv) != 2:
    print('Invalid arguments')
    print('Usage: %s VMLINUX_BINARY' % sys.argv[0])
    sys.exit(-1)

kelf = open(sys.argv[1], 'rb')
elffile = ELFFile(kelf)
entry = elffile['e_entry']

for segment in elffile.iter_segments():
    if segment['p_type'] == 'PT_LOAD':
        load_segments.append(segment)

kc = open('kernel.c', 'w')
kc.write('#include <stddef.h>\n')
kc.write('__attribute__ ((aligned (4096))) char KERNEL_BUNDLE[] = \n"')

col = 0
pos = 0
prev_paddr = None
for segment in load_segments:
    if prev_paddr == None:
        prev_paddr = segment['p_paddr']
    else:
        offset = segment['p_paddr'] - prev_paddr
        prev_addr = segment['p_paddr']
        for i in range(offset - pos):
            kc.write('\\x0')
            if col == 20:
                kc.write('"\n"')
                col = 0
            else:
                col = col + 1
                pos = offset

    for byte in segment.data():
        kc.write('\\x' + format(byte, 'x'))
        if col == 20:
            kc.write('"\n"')
            col = 0
        else:
            col = col + 1
            
    pos = pos + segment['p_filesz']
        
kc.write('";\n')
kc.write('size_t KERNEL_SIZE = 0x%s;\n' % format(pos, 'x'))
kc.write('size_t KERNEL_LOAD_ADDR = 0x%s;\n' % format(entry, 'x'))
kc.write(footer)
