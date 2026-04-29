import argparse
import sys

from elftools.elf.elffile import ELFFile

PAGE_SIZE_DEFAULT = 65536  # 64k covers 4k/16k/64k Linux kernels
PAGE_SIZE_WINDOWS = 4096   # x86_64 Windows / WHP uses 4k pages
AARCH64_LOAD_ADDR = '0x80000000'

def write_header(ofile, bundle_name, page_size):
    ofile.write('#include <stddef.h>\n')
    ofile.write('__attribute__ ((aligned ({}))) char {}_BUNDLE[] = \n"'.format(page_size, bundle_name))


def write_padding(ofile, padding, col):
    while padding > 0:
        ofile.write('\\x0')

        if col == 15:
            ofile.write('"\n"')
            col = 0
        else:
            col = col + 1
            
        padding = padding - 1
        
        
def write_elf_cbundle(ifile, ofile, page_size) -> int:
    elffile = ELFFile(ifile)
    entry_addr = elffile['e_entry']

    load_segments = [ ]
    for segment in elffile.iter_segments():
        if segment['p_type'] == 'PT_LOAD':
            load_segments.append(segment)
        
    col = 0
    total_size = 0
    prev_paddr = None

    for segment in load_segments:
        if prev_paddr == None:
            load_addr = segment['p_vaddr'] & 0xfffffff
        else:
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

    rounded_size = int((total_size + page_size - 1) / page_size) * page_size
    padding = rounded_size - total_size    
    write_padding(ofile, padding, col)

    return load_addr, entry_addr

    
def write_raw_cbundle(ifile, ofile, page_size) -> int:
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

    rounded_size = int((total_size + page_size - 1) / page_size) * page_size
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

    
def write_footer_kernel(ofile, load_addr, entry_addr):
    footer = """
char * krunfw_get_kernel(size_t *load_addr, size_t *entry_addr, size_t *size)
{{
    *load_addr = {};
    *entry_addr = {};
    *size = sizeof(KERNEL_BUNDLE) - 1;
    return &KERNEL_BUNDLE[0];
}}

int krunfw_get_version()
{{
    return ABI_VERSION;
}}
"""
    ofile.write('";\n')
    ofile.write(footer.format(load_addr, entry_addr))
    

def main() -> int:
    parser = argparse.ArgumentParser(description='Generate C blob from a binary')
    
    parser.add_argument('input_file', type=str,
                        help='Input file')
    parser.add_argument('output_file', type=str,
                        help='Output file')
    parser.add_argument('-t', type=str, help='Bundle type (vmlinux, Image, qboot, initrd)')
    parser.add_argument('--os', type=str, default='Linux',
                        help='Target OS (Linux, Darwin, Windows)')
    
    args = parser.parse_args()

    page_size = PAGE_SIZE_WINDOWS if args.os == 'Windows' else PAGE_SIZE_DEFAULT

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

    write_header(ofile, bundle_name, page_size)

    if ifmt == 'elf':
        load_addr, entry_addr = write_elf_cbundle(ifile, ofile, page_size)
    elif ifmt == 'raw':
        write_raw_cbundle(ifile, ofile, page_size)

    if bundle_name == 'KERNEL':
        if ifmt == 'raw':
            load_addr = AARCH64_LOAD_ADDR;
            entry_addr = AARCH64_LOAD_ADDR;
        write_footer_kernel(ofile, load_addr, entry_addr)
    else:
        write_footer_generic(ofile, bundle_name)

    return 0


if __name__ == '__main__':
    sys.exit(main())
