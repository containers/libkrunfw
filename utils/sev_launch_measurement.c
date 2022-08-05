#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <dlfcn.h>
#include <openssl/sha.h>


int SHA256_Init(SHA256_CTX *c);
int SHA256_Update(SHA256_CTX *c, const void *data, size_t len);
int SHA256_Final(unsigned char *md, SHA256_CTX *c);
unsigned char *SHA256(const unsigned char *d, size_t n,
                       unsigned char *md);

int main(int argc, char **argv)
{
    char * (*krunfw_get_kernel) (size_t *load_addr, size_t *size);
    char * (*krunfw_get_initrd) (size_t *size);
    char * (*krunfw_get_qboot) (size_t *size);
    char *payload_addr;
    size_t payload_size;
    size_t load_addr;
    void *handle;
    SHA256_CTX shactx;
    char digest[33];
    int i;

    if (argc != 2) {
        printf("Usage: %s LIBKRUNFW_SO\n", argv[0]);
        exit(-1);
    }

    handle = dlopen(argv[1], RTLD_NOW);
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

    SHA256_Init(&shactx);

    payload_addr = krunfw_get_qboot(&payload_size);
    printf("qboot: 0x%x, %lu\n", payload_addr, payload_size);
    SHA256_Update(&shactx, payload_addr, payload_size);

    payload_addr = krunfw_get_kernel(&load_addr, &payload_size);
    printf("kernel: 0x%x, %lu\n", payload_addr, payload_size);
    SHA256_Update(&shactx, payload_addr, payload_size);

    payload_addr = krunfw_get_initrd(&payload_size);
    printf("initrd: 0x%x, %lu\n", payload_addr, payload_size);
    SHA256_Update(&shactx, payload_addr, payload_size);

    SHA256_Final(&digest[0], &shactx);

    for (i = 0; i < 32; ++i) {
        printf("%02lx", digest[i] & 0xFFl);
    }

    printf("\n");

    return 0;
}
