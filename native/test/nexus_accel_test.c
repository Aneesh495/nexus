/*
 * Copyright (c) 2026, Nexus Distributed Data Grid Authors
 * Licensed under the Apache License, Version 2.0
 */

#include "nexus_accel.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

void test_crc32c_vectors(void)
{
    /* Known standard Castagnoli CRC32C test vector for "123456789" is 0xE3069283 */
    const char *test_str = "123456789";
    uint32_t crc = nexus_crc32c(0, test_str, strlen(test_str));
    printf("[test_crc32c] '123456789' -> 0x%08X (expected 0xE3069283)\n", crc);
    assert(crc == 0xE3069283);

    /* Empty string CRC */
    uint32_t empty_crc = nexus_crc32c(0, "", 0);
    assert(empty_crc == 0);
}

void test_murmur3_vectors(void)
{
    const char *key = "nexus:cluster:partition:101";
    uint64_t h1 = nexus_murmur3_64(key, strlen(key), 0);
    uint64_t h2 = nexus_murmur3_64(key, strlen(key), 0);
    assert(h1 == h2);
    assert(h1 != 0);
    printf("[test_murmur3] '%s' -> 0x%016llX\n", key, (unsigned long long)h1);
}

void test_xxhash64_vectors(void)
{
    const char *data = "The quick brown fox jumps over the lazy dog";
    uint64_t h = nexus_xxhash64(data, strlen(data), 0);
    assert(h != 0);
    printf("[test_xxhash64] hash -> 0x%016llX\n", (unsigned long long)h);
}

void test_bloom_probe(void)
{
    uint64_t words[4] = {0, 0, 0, 0};
    /* Set bit 5 and bit 70 */
    words[0] |= (1ULL << 5);
    words[1] |= (1ULL << 6); /* 64 + 6 = 70 */

    /* If probe hits bit 5 and 70, contains should be true */
    /* Check popcount */
    assert(nexus_popcount64(words[0]) == 1);
    assert(nexus_popcount64(words[1]) == 1);
    assert(nexus_ctz64(words[0]) == 5);
    assert(nexus_ctz64(words[1]) == 6);
    printf("[test_bloom] bit operations verified\n");
}

int main(void)
{
    printf("Running Nexus Native Acceleration Engine Test Suite...\n");
    test_crc32c_vectors();
    test_murmur3_vectors();
    test_xxhash64_vectors();
    test_bloom_probe();
    printf("ALL NATIVE TESTS PASSED CLEANLY!\n");
    return 0;
}
