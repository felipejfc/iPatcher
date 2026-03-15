#ifndef PATTERN_SCANNER_H
#define PATTERN_SCANNER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "../Shared/iPatcherConstants.h"

typedef struct {
    uint8_t bytes[IP_PATTERN_MAX_LEN];
    uint8_t mask[IP_PATTERN_MAX_LEN]; // 0xFF = exact match, 0x00 = wildcard
    size_t length;
} IPPattern;

typedef struct {
    uintptr_t addresses[IP_MAX_MATCHES];
    size_t count;
} IPScanResult;

// Parse hex pattern string like "f4 4f be a9 ?? ?? 01 a9" into IPPattern
bool ip_pattern_parse(const char *hex_string, IPPattern *out_pattern);

// Scan a memory buffer for the pattern (NEON SIMD accelerated)
IPScanResult ip_scan_buffer(const void *buffer, size_t buffer_size,
                            uintptr_t base_address, const IPPattern *pattern);

// Scan only the main executable's __TEXT segments (fast path)
IPScanResult ip_scan_main_executable(const IPPattern *pattern);

// Scan the main executable for multiple patterns in one pass.
void ip_scan_main_executable_many(const IPPattern *patterns, size_t pattern_count,
                                  IPScanResult *results);

// Scan all executable memory regions of the current process (slow fallback)
IPScanResult ip_scan_process(const IPPattern *pattern);

#endif
