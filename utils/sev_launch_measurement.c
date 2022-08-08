#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <dlfcn.h>
#include <openssl/sha.h>
#include <unistd.h>

#include "vmsa.h"


int SHA256_Init(SHA256_CTX *c);
int SHA256_Update(SHA256_CTX *c, const void *data, size_t len);
int SHA256_Final(unsigned char *md, SHA256_CTX *c);
unsigned char *SHA256(const unsigned char *d, size_t n,
		      unsigned char *md);

char * (*krunfw_get_kernel) (size_t *load_addr, size_t *size);
char * (*krunfw_get_initrd) (size_t *size);
char * (*krunfw_get_qboot) (size_t *size);


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

	SHA256_Update(&shactx, &VMSA_BP, 4096);
	for (i = 1; i < num_cpus; i++) {
		SHA256_Update(&shactx, &VMSA_AP, sizeof(VMSA_BP));
	}

	SHA256_Final(&digest[0], &shactx);

	printf("SEV-ES (%d CPUs): ", num_cpus);
	for (i = 0; i < 32; ++i) {
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

	SHA256_Final(&digest[0], &shactx);

	printf("SEV: ");
	for (i = 0; i < 32; ++i) {
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

	while((opt = getopt(argc, argv, ":c:")) != -1)
	{
		switch(opt)
		{
		case 'c':
			if ((num_cpus = atoi(optarg)) == 0) {
				printf("Invalid number of CPUs\n");
			}
			break;
		}
	}

	library = NULL;
	if (optind >= argc) {
		printf("Usage: %s [-c NUM_CPUS] LIBKRUNFW_SO\n", argv[0]);
		exit(-1);
	} else {
		library = argv[optind];
	}

	handle = dlopen(library, RTLD_NOW);
	if (handle == NULL) {
		perror("Couldn't open library");
		exit(-1);
	}

	krunfw_get_kernel = dlsym(handle, "krunfw_get_kernel");
	if (krunfw_get_kernel == NULL) {
		perror("Couldn't find krunfw_get_kernel symbol");
		exit(-1);
	}

	krunfw_get_initrd = dlsym(handle, "krunfw_get_initrd");
	if (krunfw_get_initrd == NULL) {
		perror("Couldn't find krunfw_get_initrd symbol");
		exit(-1);
	}

	krunfw_get_qboot = dlsym(handle, "krunfw_get_qboot");
	if (krunfw_get_qboot == NULL) {
		perror("Couldn't find krunfw_get_qboot symbol");
		exit(-1);
	}

	measurement_sev();
	measurement_sev_es(num_cpus);

	return 0;
}
