/*
 * Copyright (c) 2026, Nexus Distributed Data Grid Authors
 * Licensed under the Apache License, Version 2.0
 */

#ifndef NEXUS_ACCEL_H
#define NEXUS_ACCEL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * CRC32C (Castagnoli 0x82F63B78) Hardware-Accelerated Computation
 */
uint32_t nexus_crc32c(uint32_t init_crc, const void *buf, size_t len);

/*
 * 64-bit MurmurHash3 implementation
 */
uint64_t nexus_murmur3_64(const void *key, size_t len, uint64_t seed);

/*
 * 64-bit xxHash implementation
 */
uint64_t nexus_xxhash64(const void *input, size_t len, uint64_t seed);

/*
 * SIMD-accelerated Bloom Filter multi-hash batch probe
 * Computes k hash offsets and checks bit array words in a single pass.
 */
bool nexus_bloom_contains(const uint64_t *words, size_t word_count,
                          uint64_t h1, uint64_t h2, uint32_t k);

/*
 * Hardware popcount for bitset acceleration
 */
uint64_t nexus_popcount64(uint64_t v);

/*
 * Count trailing zeros for bitset scan
 */
uint32_t nexus_ctz64(uint64_t v);

#ifdef __cplusplus
}
#endif

#endif /* NEXUS_ACCEL_H */
