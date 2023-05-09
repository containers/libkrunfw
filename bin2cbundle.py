try:
    from elftools.elf.elffile import ELFFile
except:
    pass
import argparse
import sys

# Use 64k page size for rounding. This should cover 4k/16k/64k kernels
PAGE_SIZE = 65536
AARCH64_LOAD_ADDR = '0x80000000'

def write_header(ofile, bundle_name):
    ofile.write('#include <stddef.h>\n')
    ofile.write('__attribute__ ((aligned ({}))) char {}_BUNDLE[] = \n"'.format(PAGE_SIZE, bundle_name))


def write_padding(ofile, padding, col):
    while padding > 0:
        ofile.write('\\x0')

        if col == 15:
            ofile.write('"\n"')
            col = 0
        else:
            col = col + 1
            
        padding = padding - 1
        
        
def write_elf_cbundle(ifile, ofile) -> int:
    elffile = ELFFile(ifile)
    entry = elffile['e_entry']

    load_segments = [ ]
    for segment in elffile.iter_segments():
        if segment['p_type'] == 'PT_LOAD':
            load_segments.append(segment)
        
    col = 0
    total_size = 0
    prev_paddr = None
    load_addr = elffile['e_entry']

    for segment in load_segments:
        if prev_paddr != None:
            padding = segment['p_paddr'] - prev_paddr - prev_filesz
            write_padding(ofile, padding, col)
            total_size = total_size + padding

        assert((segment['p_paddr'] - load_addr) == total_size)
        
        for byte in segment.data():
            ofile.write('\\x{:x}'.format(byte))
                
            if col == 15:
                ofile.write('"\n"')
                col = 0
            else:
                col = col + 1

        prev_paddr = segment['p_paddr']
        prev_filesz = segment['p_filesz']
        total_size = total_size + prev_filesz

    rounded_size = int((total_size + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE
    padding = rounded_size - total_size    
    write_padding(ofile, padding, col)

    return load_addr

    
def write_raw_cbundle(ifile, ofile) -> int:
    col = 0
    total_size = 0
    byte = ifile.read(1)
    while byte:
        ofile.write('\\x{:x}'.format(byte[0]))
            
        if col == 15:
            ofile.write('"\n"')
            col = 0
        else:
            col = col + 1
        
        total_size = total_size + 1
        byte = ifile.read(1)

    rounded_size = int((total_size + PAGE_SIZE - 1) / PAGE_SIZE) * PAGE_SIZE
    padding = rounded_size - total_size    
    write_padding(ofile, padding, col)

    
def write_footer_generic(ofile, bundle_name):
    footer = """
char * krunfw_get_{}(size_t *size)
{{
    *size = sizeof({}_BUNDLE) - 1;
    return &{}_BUNDLE[0];
}}
"""
    ofile.write('";\n')
    ofile.write(footer.format(bundle_name.lower(), bundle_name, bundle_name))

    
def write_footer_kernel(ofile, load_addr):
    footer = """
char * krunfw_get_kernel(size_t *load_addr, size_t *size)
{{
    *load_addr = {};
    *size = sizeof(KERNEL_BUNDLE) - 1;
    return &KERNEL_BUNDLE[0];
}}

int krunfw_get_version()
{{
    return ABI_VERSION;
}}
"""
    ofile.write('";\n')
    ofile.write(footer.format(load_addr))
    

def main() -> int:
    parser = argparse.ArgumentParser(description='Generate C blob from a binary')
    
    parser.add_argument('input_file', type=str,
                        help='Input file')
    parser.add_argument('output_file', type=str,
                        help='Output file')
    parser.add_argument('-t', type=str, help='Bundle type (vmlinux, Image, qboot, initrd)')
    
    args = parser.parse_args()

    bundle_name = None
    ifmt = None
    if args.t == 'vmlinux':
        bundle_name = 'KERNEL'
        ifmt = 'elf'
    elif args.t == 'Image':
        bundle_name = 'KERNEL'
        ifmt = 'raw'
    elif args.t == 'qboot':
        bundle_name = 'QBOOT'
        ifmt = 'raw'
    elif args.t == 'initrd':
        bundle_name = 'INITRD'
        ifmt = 'raw'
    else:
        print('Invalid bundle type')
        return -1

    ifile = open(args.input_file, 'rb')
    ofile = open(args.output_file, 'w')

    write_header(ofile, bundle_name)

    if ifmt == 'elf':
        load_addr = write_elf_cbundle(ifile, ofile)
    elif ifmt == 'raw':
        write_raw_cbundle(ifile, ofile)

    if bundle_name == 'KERNEL':
        if ifmt == 'raw':
            load_addr = AARCH64_LOAD_ADDR;
        write_footer_kernel(ofile, load_addr)
    else:
        write_footer_generic(ofile, bundle_name)

    return 0


if __name__ == '__main__':
    sys.exit(main())
