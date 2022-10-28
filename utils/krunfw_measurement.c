#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <openssl/sha.h>
#include <unistd.h>
#include <asm/bootparam.h>

#include "vmsa.h"

#define EBDA_START              0x9fc00
#define HIMEM_START             0x100000
#define MMIO_MEM_START          0xd0000000
#define FIRST_ADDR_PAST_32BITS  0x100000000

#define KERNEL_LOADER_OTHER     0xff
#define KERNEL_BOOT_FLAG_MAGIC  0xaa55
#define KERNEL_HDR_MAGIC        0x53726448
#define KERNEL_MIN_ALIGNMENT    0x01000000

#define KRUN_CMDLINE_ADDR       0x20000
#define KRUN_CMDLINE_SIZE       0x200

#define KRUN_RAMDISK_ADDR       0xa00000
#define KRUN_RAMDISK_SIZE       0x19e000

struct page_info
{
	uint8_t current[48];
	uint8_t contents[48];
	uint16_t length;
	uint8_t page_type;
	uint8_t imi_page : 1; // bit 0
	uint8_t reserved : 7; // bits 1 to 7
	uint8_t resv;
	uint8_t vmpl_1_perms;
	uint8_t vmpl_2_perms;
	uint8_t vmpl_3_perms;
	uint64_t gpa;
} __attribute__((__packed__));

char *(*krunfw_get_kernel)(size_t *load_addr, size_t *size);
char *(*krunfw_get_initrd)(size_t *size);
char *(*krunfw_get_qboot)(size_t *size);

struct boot_params bootp;

void setup_bootp(int num_cpus, int ram_mib)
{
	unsigned long long mem_size;

	memset(&bootp, 0, sizeof(bootp));

	bootp.hdr.type_of_loader = KERNEL_LOADER_OTHER;
	bootp.hdr.boot_flag = KERNEL_BOOT_FLAG_MAGIC;
	bootp.hdr.header = KERNEL_HDR_MAGIC;
	bootp.hdr.kernel_alignment = KERNEL_MIN_ALIGNMENT;

	bootp.hdr.cmd_line_ptr = KRUN_CMDLINE_ADDR;
	bootp.hdr.cmdline_size = KRUN_CMDLINE_SIZE;

	bootp.hdr.ramdisk_image = KRUN_RAMDISK_ADDR;

	bootp.hdr.syssize = num_cpus;

	bootp.e820_table[0].addr = 0;
	bootp.e820_table[0].size = EBDA_START;
	bootp.e820_table[0].type = 1;

	mem_size = ((unsigned long long)ram_mib) * 1024 * 1024;
	if (mem_size <= MMIO_MEM_START)
	{
		bootp.e820_table[1].addr = HIMEM_START;
		bootp.e820_table[1].size = mem_size - HIMEM_START + 1;
		bootp.e820_table[1].type = 1;

		bootp.e820_entries = 2;
	}
	else
	{
		bootp.e820_table[1].addr = HIMEM_START;
		bootp.e820_table[1].size = MMIO_MEM_START - HIMEM_START;
		bootp.e820_table[1].type = 1;

		bootp.e820_table[2].addr = FIRST_ADDR_PAST_32BITS;
		bootp.e820_table[2].size = mem_size - MMIO_MEM_START + 1;
		bootp.e820_table[2].type = 1;

		bootp.e820_entries = 3;
	}
}

void digest_blob(char *current, char *blob, uint64_t load_addr, size_t size)
{
	int i, j;
	SHA512_CTX ctx;
	struct page_info info;


	for (i = 0; i < size; i += 4096)
	{
		memset(&info, 0, sizeof(struct page_info));

		memcpy(&info.current[0], current, 48);
		SHA384(blob + i, 4096, &info.contents[0]);

		info.length = sizeof(struct page_info);
		info.page_type = 1;
		info.gpa = load_addr + i;

		SHA384((char *)&info, sizeof(struct page_info), current);
	}
}

void digest_zero(char *current, uint64_t gaddr, size_t size, uint8_t page_type)
{
	SHA512_CTX ctx;
	struct page_info info;
	int i;

	for (i = 0; i < size; i += 4096)
	{
		memset(&info, 0, sizeof(struct page_info));
		memcpy(&info.current[0], current, 48);
		memset(&info.contents[0], 0, 48);
		info.length = sizeof(struct page_info);
		info.page_type = page_type;
		info.gpa = gaddr + i;

		SHA384((char *)&info, sizeof(struct page_info), current);
	}
}

void digest_vmsa(char *current)
{
	SHA512_CTX ctx;
	struct page_info info;

	memset(&info, 0, sizeof(struct page_info));
	memcpy(&info.current[0], current, 48);
	SHA384((char *)&SNP_VMSA_BP[0], 4096, &info.contents[0]);

	info.length = sizeof(struct page_info);
	info.page_type = 2;
	info.gpa = 0xFFFFFFFFF000;

	SHA384((char *)&info, sizeof(struct page_info), current);
}

void measurement_snp(int num_cpus)
{
	char *payload_addr;
	size_t payload_size;
	size_t load_addr;
	char digest[48] = {0};
	int i;
	int ret;

	payload_addr = krunfw_get_qboot(&payload_size);
	digest_blob(&digest[0], payload_addr, 0xffff0000, payload_size);

	payload_addr = krunfw_get_kernel(&load_addr, &payload_size);
	digest_blob(&digest[0], payload_addr, load_addr, payload_size);

	payload_addr = krunfw_get_initrd(&payload_size);
	digest_blob(&digest[0], payload_addr, 0xa00000, payload_size);

	bootp.hdr.ramdisk_size = payload_size;
	digest_blob(&digest[0], (char *)&bootp, 0x7000, 0x1000);

	digest_zero(&digest[0], 0x0, 0x1000, 4);
	digest_zero(&digest[0], 0x5000, 0x1000, 5);
	digest_zero(&digest[0], 0x6000, 0x1000, 6);
	digest_zero(&digest[0], 0x8000, 0x7000, 4);

	digest_vmsa(&digest[0]);

	printf("SNP:\t");
	for (i = 0; i < 48; ++i)
	{
		printf("%02hhx", digest[i]);
	}
	printf("\n");
}

void measurement_sev_es(int num_cpus)
{
	char *payload_addr;
	size_t payload_size;
	size_t load_addr;
	SHA256_CTX shactx;
	char digest[33];
	int i;

	SHA256_Init(&shactx);

	payload_addr = krunfw_get_qboot(&payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	payload_addr = krunfw_get_kernel(&load_addr, &payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	payload_addr = krunfw_get_initrd(&payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	bootp.hdr.ramdisk_size = payload_size;
	SHA256_Update(&shactx, &bootp, 4096);

	SHA256_Update(&shactx, &VMSA_BP, 4096);
	for (i = 1; i < num_cpus; i++)
	{
		SHA256_Update(&shactx, &VMSA_AP, 4096);
	}

	SHA256_Final(&digest[0], &shactx);

	printf("SEV-ES:\t");
	for (i = 0; i < 32; ++i)
	{
		printf("%02lx", digest[i] & 0xFFl);
	}
	printf("\n");
}

void measurement_sev()
{
	char *payload_addr;
	size_t payload_size;
	size_t load_addr;
	SHA256_CTX shactx;
	char digest[33];
	int i;

	SHA256_Init(&shactx);

	payload_addr = krunfw_get_qboot(&payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	payload_addr = krunfw_get_kernel(&load_addr, &payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	payload_addr = krunfw_get_initrd(&payload_size);
	SHA256_Update(&shactx, payload_addr, payload_size);

	bootp.hdr.ramdisk_size = payload_size;
	SHA256_Update(&shactx, &bootp, 4096);

	SHA256_Final(&digest[0], &shactx);

	printf("SEV:\t");
	for (i = 0; i < 32; ++i)
	{
		printf("%02lx", digest[i] & 0xFFl);
	}
	printf("\n");
}

int main(int argc, char **argv)
{
	void *handle;
	char *library;
	int opt;
	int num_cpus = 1;
	int ram_mib = 2048;

	while ((opt = getopt(argc, argv, ":c:m:")) != -1)
	{
		switch (opt)
		{
		case 'c':
			if ((num_cpus = atoi(optarg)) == 0)
			{
				printf("Invalid number of CPUs\n");
			}
			break;
		case 'm':
			if ((ram_mib = atoi(optarg)) == 0)
			{
				printf("Invalid amount of RAM\n");
			}
			break;
		}
	}

	library = NULL;
	if (optind >= argc)
	{
		printf("Usage: %s [-c NUM_CPUS] [-m RAM_MIB] LIBKRUNFW_SO\n", argv[0]);
		exit(-1);
	}
	else
	{
		library = argv[optind];
	}

	handle = dlopen(library, RTLD_NOW);
	if (handle == NULL)
	{
		perror("Couldn't open library");
		exit(-1);
	}

	krunfw_get_kernel = dlsym(handle, "krunfw_get_kernel");
	if (krunfw_get_kernel == NULL)
	{
		perror("Couldn't find krunfw_get_kernel symbol");
		exit(-1);
	}

	krunfw_get_initrd = dlsym(handle, "krunfw_get_initrd");
	if (krunfw_get_initrd == NULL)
	{
		perror("Couldn't find krunfw_get_initrd symbol");
		exit(-1);
	}

	krunfw_get_qboot = dlsym(handle, "krunfw_get_qboot");
	if (krunfw_get_qboot == NULL)
	{
		perror("Couldn't find krunfw_get_qboot symbol");
		exit(-1);
	}

	setup_bootp(num_cpus, ram_mib);
	printf("Measurements for %d vCPU(s) and %d MB of RAM\n",
		   num_cpus, ram_mib);
	measurement_sev();
	measurement_sev_es(num_cpus);
	measurement_snp(num_cpus);

	return 0;
}
