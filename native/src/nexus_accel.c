/*
 * Copyright (c) 2026, Nexus Distributed Data Grid Authors
 * Licensed under the Apache License, Version 2.0
 */

#include "nexus_accel.h"
#include <string.h>

#if defined(__ARM_FEATURE_CRC32)
#include <arm_acle.h>
#endif

#if !defined(__ARM_FEATURE_CRC32)
/*
 * Castagnoli polynomial table for software fallback
 */
static const uint32_t CRC32C_TABLE[256] = {
    0x00000000, 0xF26B8303, 0xE13B70F7, 0x1350F3F4,
    0xC79A971F, 0x35F1141C, 0x26A1E7E8, 0xD4CA64EB,
    0x8AD958CF, 0x78B2DBCC, 0x6BE22838, 0x9989AB3B,
    0x4D43CFD0, 0xBF284CD3, 0xAC78BF27, 0x5E133C24,
    0x105EC76F, 0xE235446C, 0xF165B798, 0x030E349B,
    0xD7C45070, 0x25AFD373, 0x36FF2087, 0xC494A384,
    0x9A879FA0, 0x68EC1CA3, 0x7BBCEF57, 0x89D76C54,
    0x5D1D08BF, 0xAF768BBC, 0xBC267848, 0x4E4DFB4B,
    0x20BD8EDE, 0xD2D60DDD, 0xC186FE29, 0x33ED7D2A,
    0xE72719C1, 0x154C9AC2, 0x061C6936, 0xF477EA35,
    0xAA64D611, 0x580F5512, 0x4B5FA6E6, 0xB93425E5,
    0x6DFE410E, 0x9F95C20D, 0x8CC531F9, 0x7EAEB2FA,
    0x30E349B1, 0xC288CAB2, 0xD1D83946, 0x23B3BA45,
    0xF779DEAE, 0x05125DAD, 0x1642AE59, 0xE4292D5A,
    0xBA3A117E, 0x4851927D, 0x5B016189, 0xA96AE28A,
    0x7DA08661, 0x8FCB0562, 0x9C9BF696, 0x6EF07595,
    0x417B1DBC, 0xB3109EBF, 0xA0406D4B, 0x522BEE48,
    0x86E18AA3, 0x748A09A0, 0x67DAFA54, 0x95B17957,
    0xCBA24573, 0x39C9C670, 0x2A993584, 0xD8F2B687,
    0x0C38D26C, 0xFE53516F, 0xED03A29B, 0x1F682198,
    0x5125DAD3, 0xA34E59D0, 0xB01EAD24, 0x42752E27,
    0x96BF4DCC, 0x64D4CECF, 0x77843D3B, 0x85EFBE38,
    0xDBFC821C, 0x2997011F, 0x3AC7F2EB, 0xC8AC71E8,
    0x1C661503, 0xEE0D9600, 0xFD5D65F4, 0x0F36E6F7,
    0x61C69362, 0x93AD1061, 0x80FDE395, 0x72966096,
    0xA65C047D, 0x5437877E, 0x4767748A, 0xB50CF789,
    0xEB1FCBAD, 0x197448AE, 0x0A24BB5A, 0xF84F3859,
    0x2C855CB2, 0xDEEEDFB1, 0xCDBE2C45, 0x3FD5AF46,
    0x7198540D, 0x83F3D70E, 0x90A324FA, 0x62C8A7F9,
    0xB602C312, 0x44694011, 0x5739B3E5, 0xA55230E6,
    0xFB410CC2, 0x092A8FC1, 0x1A7A7C35, 0xE811FF36,
    0x3CDB9BDD, 0xCEB018DE, 0xDDE0EB2A, 0x2F8B6829,
    0x82F63B78, 0x709DB87B, 0x63CD4B8F, 0x91A6C88C,
    0x456CAC67, 0xB7072F64, 0xA457DC90, 0x563C5F93,
    0x082F63B7, 0xFA44E0B4, 0xE9141340, 0x1B7F9043,
    0xCFB5F4A8, 0x3DDE77AB, 0x2E8E845F, 0xDCE5075C,
    0x92A8FC17, 0x60C37F14, 0x73938CE0, 0x81F80FE3,
    0x55326B08, 0xA759E80B, 0xB4091BFF, 0x466298FC,
    0x1871A4D8, 0xEA1A27DB, 0xF94AD42F, 0x0B21572C,
    0xDFEB33C7, 0x2D80B0C4, 0x3ED04330, 0xCCBBC033,
    0xA24BB5A6, 0x502036A5, 0x4370C551, 0xB11B4652,
    0x65D122B9, 0x97BAA1BA, 0x84EA524E, 0x7681D14D,
    0x2892ED69, 0xDAF96E6A, 0xC9A99D9E, 0x3BC21E9D,
    0xEF087A76, 0x1D63F975, 0x0E330A81, 0xFC588982,
    0xB21572C9, 0x407EF1CA, 0x532E023E, 0xA145813D,
    0x758FE5D6, 0x87E466D5, 0x94B49521, 0x66DF1622,
    0x38CC2A06, 0xCAA7A905, 0xD9F75AF1, 0x2B9CD9F2,
    0xFF56BD19, 0x0D3D3E1A, 0x1E6DCDEE, 0xEC064EED,
    0xC38D26C4, 0x31E6A5C7, 0x22B65633, 0xD0DDD530,
    0x0417B1DB, 0xF67C32D8, 0xE52CC12C, 0x1747422F,
    0x49547E0B, 0xBB3FFD08, 0xA86F0EFC, 0x5A048DFF,
    0x8ECEE914, 0x7CA56A17, 0x6FF599E3, 0x9D9E1AE0,
    0xD3D3E1AB, 0x21B862A8, 0x32E8915C, 0xC083125F,
    0x144976B4, 0xE622F5B7, 0xF5720643, 0x07198540,
    0x590AB964, 0xAB613A67, 0xB831C993, 0x4A5A4A90,
    0x9E902E7B, 0x6CFBAD78, 0x7FAB5E8C, 0x8DC0DD8F,
    0xE330A81A, 0x115B2B19, 0x020BD8ED, 0xF0605BEE,
    0x24AA3F05, 0xD6C1BC06, 0xC5914FF2, 0x37FACCF1,
    0x69E9F0D5, 0x9B8273D6, 0x88D28022, 0x7AB90321,
    0xAE7367CA, 0x5C18E4C9, 0x4F48173D, 0xBD23943E,
    0xF36E6F75, 0x0105EC76, 0x12551F82, 0xE03E9C81,
    0x34F4F86A, 0xC69F7B69, 0xD5CF889D, 0x27A40B9E,
    0x79B737BA, 0x8BDCB4B9, 0x988C474D, 0x6AE7C44E,
    0xBE2DA0A5, 0x4C4623A6, 0x5F16D052, 0xAD7D5351
};
#endif

uint32_t nexus_crc32c(uint32_t init_crc, const void *buf, size_t len)
{
    const uint8_t *p = (const uint8_t *)buf;
    uint32_t crc = ~init_crc;

#if defined(__ARM_FEATURE_CRC32)
    while (len >= 8) {
        uint64_t val;
        memcpy(&val, p, 8);
        crc = __crc32cd(crc, val);
        p += 8;
        len -= 8;
    }
    while (len > 0) {
        crc = __crc32cb(crc, *p++);
        len--;
    }
    return ~crc;
#else
    while (len--) {
        crc = CRC32C_TABLE[(crc ^ *p++) & 0xFF] ^ (crc >> 8);
    }
    return ~crc;
#endif
}

static inline uint64_t rotl64(uint64_t x, int8_t r)
{
    return (x << r) | (x >> (64 - r));
}

static inline uint64_t fmix64(uint64_t k)
{
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    return k;
}

uint64_t nexus_murmur3_64(const void *key, size_t len, uint64_t seed)
{
    const uint8_t *data = (const uint8_t *)key;
    const size_t nblocks = len / 16;

    uint64_t h1 = seed;
    uint64_t h2 = seed;

    const uint64_t c1 = 0x87c37b91114253d5ULL;
    const uint64_t c2 = 0x4cf5ad432745937fULL;

    for (size_t i = 0; i < nblocks; i++) {
        uint64_t k1;
        uint64_t k2;
        memcpy(&k1, data + i * 16, 8);
        memcpy(&k2, data + i * 16 + 8, 8);

        k1 *= c1;
        k1 = rotl64(k1, 31);
        k1 *= c2;
        h1 ^= k1;

        h1 = rotl64(h1, 27);
        h1 += h2;
        h1 = h1 * 5 + 0x52dce729;

        k2 *= c2;
        k2 = rotl64(k2, 33);
        k2 *= c1;
        h2 ^= k2;

        h2 = rotl64(h2, 31);
        h2 += h1;
        h2 = h2 * 5 + 0x38495ab5;
    }

    const uint8_t *tail = (const uint8_t *)(data + nblocks * 16);
    uint64_t k1 = 0;
    uint64_t k2 = 0;

    switch (len & 15) {
        case 15: k2 ^= ((uint64_t)tail[14]) << 48;
        case 14: k2 ^= ((uint64_t)tail[13]) << 40;
        case 13: k2 ^= ((uint64_t)tail[12]) << 32;
        case 12: k2 ^= ((uint64_t)tail[11]) << 24;
        case 11: k2 ^= ((uint64_t)tail[10]) << 16;
        case 10: k2 ^= ((uint64_t)tail[9]) << 8;
        case 9:  k2 ^= ((uint64_t)tail[8]) << 0;
                 k2 *= c2; k2 = rotl64(k2, 33); k2 *= c1; h2 ^= k2;
        case 8:  k1 ^= ((uint64_t)tail[7]) << 56;
        case 7:  k1 ^= ((uint64_t)tail[6]) << 48;
        case 6:  k1 ^= ((uint64_t)tail[5]) << 40;
        case 5:  k1 ^= ((uint64_t)tail[4]) << 32;
        case 4:  k1 ^= ((uint64_t)tail[3]) << 24;
        case 3:  k1 ^= ((uint64_t)tail[2]) << 16;
        case 2:  k1 ^= ((uint64_t)tail[1]) << 8;
        case 1:  k1 ^= ((uint64_t)tail[0]) << 0;
                 k1 *= c1; k1 = rotl64(k1, 31); k1 *= c2; h1 ^= k1;
    }

    h1 ^= len;
    h2 ^= len;

    h1 += h2;
    h2 += h1;

    h1 = fmix64(h1);
    h2 = fmix64(h2);

    h1 += h2;
    return h1;
}

uint64_t nexus_xxhash64(const void *input, size_t len, uint64_t seed)
{
    const uint64_t PRIME64_1 = 0x9E3779B185EBCA87ULL;
    const uint64_t PRIME64_2 = 0xC2B2AE3D27D4EB4FULL;
    const uint64_t PRIME64_3 = 0x165667B19E3779F9ULL;
    const uint64_t PRIME64_4 = 0x85EBCA77C2B2AE63ULL;
    const uint64_t PRIME64_5 = 0x27D4EB2F165667C5ULL;

    const uint8_t *p = (const uint8_t *)input;
    uint64_t h64;

    if (len >= 32) {
        uint64_t v1 = seed + PRIME64_1 + PRIME64_2;
        uint64_t v2 = seed + PRIME64_2;
        uint64_t v3 = seed + 0;
        uint64_t v4 = seed - PRIME64_1;

        const uint8_t *limit = p + len - 32;
        do {
            uint64_t k1, k2, k3, k4;
            memcpy(&k1, p, 8);
            memcpy(&k2, p + 8, 8);
            memcpy(&k3, p + 16, 8);
            memcpy(&k4, p + 24, 8);

            v1 = rotl64(v1 + k1 * PRIME64_2, 31) * PRIME64_1;
            v2 = rotl64(v2 + k2 * PRIME64_2, 31) * PRIME64_1;
            v3 = rotl64(v3 + k3 * PRIME64_2, 31) * PRIME64_1;
            v4 = rotl64(v4 + k4 * PRIME64_2, 31) * PRIME64_1;
            p += 32;
        } while (p <= limit);

        h64 = rotl64(v1, 1) + rotl64(v2, 7) + rotl64(v3, 12) + rotl64(v4, 18);
        v1 *= PRIME64_2; v1 = rotl64(v1, 31); v1 *= PRIME64_1; h64 ^= v1; h64 = h64 * PRIME64_1 + PRIME64_4;
        v2 *= PRIME64_2; v2 = rotl64(v2, 31); v2 *= PRIME64_1; h64 ^= v2; h64 = h64 * PRIME64_1 + PRIME64_4;
        v3 *= PRIME64_2; v3 = rotl64(v3, 31); v3 *= PRIME64_1; h64 ^= v3; h64 = h64 * PRIME64_1 + PRIME64_4;
        v4 *= PRIME64_2; v4 = rotl64(v4, 31); v4 *= PRIME64_1; h64 ^= v4; h64 = h64 * PRIME64_1 + PRIME64_4;
    } else {
        h64 = seed + PRIME64_5;
    }

    h64 += (uint64_t)len;

    while (len >= 8) {
        uint64_t k1;
        memcpy(&k1, p, 8);
        k1 *= PRIME64_2;
        k1 = rotl64(k1, 31);
        k1 *= PRIME64_1;
        h64 ^= k1;
        h64 = rotl64(h64, 27) * PRIME64_1 + PRIME64_4;
        p += 8;
        len -= 8;
    }

    if (len >= 4) {
        uint32_t k1;
        memcpy(&k1, p, 4);
        h64 ^= (uint64_t)(k1) * PRIME64_1;
        h64 = rotl64(h64, 23) * PRIME64_2 + PRIME64_3;
        p += 4;
        len -= 4;
    }

    while (len > 0) {
        h64 ^= (*p++) * PRIME64_5;
        h64 = rotl64(h64, 11) * PRIME64_1;
        len--;
    }

    h64 ^= h64 >> 33;
    h64 *= PRIME64_2;
    h64 ^= h64 >> 29;
    h64 *= PRIME64_3;
    h64 ^= h64 >> 32;

    return h64;
}

bool nexus_bloom_contains(const uint64_t *words, size_t word_count,
                          uint64_t h1, uint64_t h2, uint32_t k)
{
    if (word_count == 0) return false;
    uint64_t bit_count = word_count * 64;

    for (uint32_t i = 0; i < k; i++) {
        uint64_t combined = h1 + (uint64_t)i * h2;
        uint64_t bit_idx = (combined & 0x7FFFFFFFFFFFFFFFULL) % bit_count;
        uint64_t word_idx = bit_idx >> 6;
        uint64_t bit_offset = bit_idx & 63;

        if ((words[word_idx] & (1ULL << bit_offset)) == 0) {
            return false;
        }
    }
    return true;
}

uint64_t nexus_popcount64(uint64_t v)
{
    return (uint64_t)__builtin_popcountll(v);
}

uint32_t nexus_ctz64(uint64_t v)
{
    return v == 0 ? 64 : (uint32_t)__builtin_ctzll(v);
}
