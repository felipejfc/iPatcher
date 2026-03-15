#include "PatternScanner.h"
#include <arm_neon.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    IPPattern pattern;
    uint16_t fixed_offsets[IP_PATTERN_MAX_LEN];
    uint8_t fixed_bytes[IP_PATTERN_MAX_LEN];
    uint16_t verify_offsets[IP_PATTERN_MAX_LEN];
    uint8_t verify_bytes[IP_PATTERN_MAX_LEN];
    uint16_t fixed_count;
    uint16_t verify_count;
    uint16_t anchor_off;
    uint16_t literal_off;
    uint16_t literal_len;
    uint8_t anchor_byte;
    bool valid;
    bool has_anchor;
} IPCompiledPattern;

// ---------------------------------------------------------------------------
// Hex parsing
// ---------------------------------------------------------------------------

static inline int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

bool ip_pattern_parse(const char *hex_string, IPPattern *out) {
    if (!hex_string || !out) return false;
    memset(out, 0, sizeof(IPPattern));

    size_t idx = 0;
    const char *p = hex_string;

    while (*p && idx < IP_PATTERN_MAX_LEN) {
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
        if (!*p) break;

        if (p[0] == '?' && p[1] == '?') {
            out->bytes[idx] = 0x00;
            out->mask[idx] = 0x00;
            idx++;
            p += 2;
            continue;
        }

        int hi = hex_val(p[0]);
        if (hi < 0) return false;
        int lo = p[1] ? hex_val(p[1]) : -1;
        if (lo < 0) return false;

        out->bytes[idx] = (uint8_t)((hi << 4) | lo);
        out->mask[idx] = 0xFF;
        idx++;
        p += 2;
    }

    out->length = idx;
    return idx > 0;
}

// ---------------------------------------------------------------------------
// Compiled pattern helpers
// ---------------------------------------------------------------------------

static bool ip_compile_pattern(const IPPattern *pattern, IPCompiledPattern *out) {
    if (!pattern || !out || pattern->length == 0 || pattern->length > IP_PATTERN_MAX_LEN) {
        return false;
    }

    memset(out, 0, sizeof(*out));
    out->pattern = *pattern;
    out->valid = true;

    size_t best_run_start = 0;
    size_t best_run_len = 0;
    size_t run_start = 0;
    size_t run_len = 0;

    for (size_t i = 0; i < pattern->length; i++) {
        if (pattern->mask[i] == 0xFF) {
            out->fixed_offsets[out->fixed_count] = (uint16_t)i;
            out->fixed_bytes[out->fixed_count] = pattern->bytes[i];
            out->fixed_count++;

            if (run_len == 0) run_start = i;
            run_len++;
            if (run_len > best_run_len) {
                best_run_len = run_len;
                best_run_start = run_start;
            }
        } else {
            run_len = 0;
        }
    }

    if (out->fixed_count == 0) {
        return true;
    }

    out->has_anchor = true;
    out->literal_off = (uint16_t)best_run_start;
    out->literal_len = (uint16_t)best_run_len;
    out->anchor_off = out->literal_off;
    out->anchor_byte = pattern->bytes[out->anchor_off];

    for (size_t i = 0; i < out->fixed_count; i++) {
        size_t off = out->fixed_offsets[i];
        if (off >= out->literal_off && off < (size_t)out->literal_off + out->literal_len) {
            continue;
        }
        out->verify_offsets[out->verify_count] = (uint16_t)off;
        out->verify_bytes[out->verify_count] = out->fixed_bytes[i];
        out->verify_count++;
    }

    return true;
}

static inline bool ip_verify_compiled_match(const uint8_t *data,
                                            const IPCompiledPattern *pattern) {
    if (!pattern->valid) return false;
    if (pattern->fixed_count == 0) return true;

    if (pattern->literal_len &&
        memcmp(data + pattern->literal_off,
               pattern->pattern.bytes + pattern->literal_off,
               pattern->literal_len) != 0) {
        return false;
    }

    for (size_t i = 0; i < pattern->verify_count; i++) {
        if (data[pattern->verify_offsets[i]] != pattern->verify_bytes[i]) {
            return false;
        }
    }

    return true;
}

// ---------------------------------------------------------------------------
// Single-pattern scan
// ---------------------------------------------------------------------------

static inline void ip_record_match(IPScanResult *result, uintptr_t address) {
    if (result->count < IP_MAX_MATCHES) {
        result->addresses[result->count++] = address;
    }
}

static IPScanResult ip_scan_compiled_buffer(const void *buffer, size_t buffer_size,
                                            uintptr_t base_address,
                                            const IPCompiledPattern *pattern) {
    IPScanResult result = { .count = 0 };

    if (!buffer || !pattern || pattern->pattern.length == 0 ||
        buffer_size < pattern->pattern.length) {
        return result;
    }

    const uint8_t *data = (const uint8_t *)buffer;
    const size_t scan_end = buffer_size - pattern->pattern.length;

    if (!pattern->has_anchor) {
        for (size_t i = 0; i <= scan_end && result.count < IP_MAX_MATCHES; i++) {
            result.addresses[result.count++] = base_address + i;
        }
        return result;
    }

    const uint8x16_t anchor_vec = vdupq_n_u8(pattern->anchor_byte);
    size_t i = 0;
    size_t simd_limit = buffer_size >= 16 ? buffer_size - 16 : 0;

    while (i <= simd_limit && result.count < IP_MAX_MATCHES) {
        uint8x16_t chunk = vld1q_u8(data + i);
        uint8x16_t cmp = vceqq_u8(chunk, anchor_vec);
        uint64x2_t cmp64 = vreinterpretq_u64_u8(cmp);

        if (vgetq_lane_u64(cmp64, 0) | vgetq_lane_u64(cmp64, 1)) {
            for (size_t lane = 0; lane < 16 && result.count < IP_MAX_MATCHES; lane++) {
                size_t pos = i + lane;
                if (data[pos] != pattern->anchor_byte || pos < pattern->anchor_off) continue;

                size_t cand = pos - pattern->anchor_off;
                if (cand > scan_end) continue;

                if (ip_verify_compiled_match(data + cand, pattern)) {
                    ip_record_match(&result, base_address + cand);
                }
            }
        }

        i += 16;
    }

    for (; i < buffer_size && result.count < IP_MAX_MATCHES; i++) {
        if (data[i] != pattern->anchor_byte || i < pattern->anchor_off) continue;

        size_t cand = i - pattern->anchor_off;
        if (cand > scan_end) continue;

        if (ip_verify_compiled_match(data + cand, pattern)) {
            ip_record_match(&result, base_address + cand);
        }
    }

    return result;
}

IPScanResult ip_scan_buffer(const void *buffer, size_t buffer_size,
                            uintptr_t base_address, const IPPattern *pattern) {
    IPCompiledPattern compiled;
    if (!ip_compile_pattern(pattern, &compiled)) {
        IPScanResult empty = { .count = 0 };
        return empty;
    }

    return ip_scan_compiled_buffer(buffer, buffer_size, base_address, &compiled);
}

// ---------------------------------------------------------------------------
// Multi-pattern scan
// ---------------------------------------------------------------------------

static bool ip_bucket_is_full(const size_t *pattern_indices, size_t pattern_count,
                              const IPScanResult *results) {
    for (size_t i = 0; i < pattern_count; i++) {
        if (results[pattern_indices[i]].count < IP_MAX_MATCHES) return false;
    }
    return true;
}

static void ip_check_bucket_candidates(const uint8_t *data, size_t buffer_size,
                                       uintptr_t base_address, size_t pos,
                                       const IPCompiledPattern *compiled,
                                       const size_t *pattern_indices,
                                       size_t pattern_count, IPScanResult *results) {
    for (size_t i = 0; i < pattern_count; i++) {
        size_t idx = pattern_indices[i];
        IPScanResult *result = &results[idx];
        const IPCompiledPattern *pattern = &compiled[idx];

        if (result->count >= IP_MAX_MATCHES || pos < pattern->anchor_off) continue;
        if (buffer_size < pattern->pattern.length) continue;

        size_t cand = pos - pattern->anchor_off;
        size_t scan_end = buffer_size - pattern->pattern.length;
        if (cand > scan_end) continue;

        if (ip_verify_compiled_match(data + cand, pattern)) {
            ip_record_match(result, base_address + cand);
        }
    }
}

static void ip_scan_bucketed_buffer(const void *buffer, size_t buffer_size,
                                    uintptr_t base_address,
                                    const IPCompiledPattern *compiled,
                                    const size_t *pattern_indices,
                                    size_t pattern_count, IPScanResult *results) {
    if (!buffer || !compiled || !pattern_indices || pattern_count == 0 || !results ||
        buffer_size == 0) {
        return;
    }

    if (ip_bucket_is_full(pattern_indices, pattern_count, results)) return;

    const uint8_t *data = (const uint8_t *)buffer;
    const uint8_t anchor = compiled[pattern_indices[0]].anchor_byte;
    const uint8x16_t anchor_vec = vdupq_n_u8(anchor);
    size_t i = 0;
    size_t simd_limit = buffer_size >= 16 ? buffer_size - 16 : 0;

    while (i <= simd_limit) {
        if (ip_bucket_is_full(pattern_indices, pattern_count, results)) return;

        uint8x16_t chunk = vld1q_u8(data + i);
        uint8x16_t cmp = vceqq_u8(chunk, anchor_vec);
        uint64x2_t cmp64 = vreinterpretq_u64_u8(cmp);

        if (vgetq_lane_u64(cmp64, 0) | vgetq_lane_u64(cmp64, 1)) {
            for (size_t lane = 0; lane < 16; lane++) {
                size_t pos = i + lane;
                if (data[pos] != anchor) continue;
                ip_check_bucket_candidates(data, buffer_size, base_address, pos,
                                           compiled, pattern_indices, pattern_count,
                                           results);
            }
        }

        i += 16;
    }

    for (; i < buffer_size; i++) {
        if (data[i] != anchor) continue;
        ip_check_bucket_candidates(data, buffer_size, base_address, i,
                                   compiled, pattern_indices, pattern_count,
                                   results);
    }
}

static void ip_scan_all_wildcard_patterns(uintptr_t base_address, size_t buffer_size,
                                          const IPCompiledPattern *compiled,
                                          size_t pattern_count,
                                          IPScanResult *results) {
    for (size_t i = 0; i < pattern_count; i++) {
        if (!compiled[i].valid || compiled[i].fixed_count != 0 ||
            buffer_size < compiled[i].pattern.length) {
            continue;
        }

        size_t scan_end = buffer_size - compiled[i].pattern.length;
        for (size_t off = 0; off <= scan_end && results[i].count < IP_MAX_MATCHES; off++) {
            results[i].addresses[results[i].count++] = base_address + off;
        }
    }
}

// ---------------------------------------------------------------------------
// Executable image scan
// ---------------------------------------------------------------------------

static bool ip_section_has_instructions_64(const struct section_64 *section) {
    return (section->flags & S_ATTR_PURE_INSTRUCTIONS) ||
           (section->flags & S_ATTR_SOME_INSTRUCTIONS);
}

static bool ip_section_has_instructions_32(const struct section *section) {
    return (section->flags & S_ATTR_PURE_INSTRUCTIONS) ||
           (section->flags & S_ATTR_SOME_INSTRUCTIONS);
}

static void ip_scan_region_many(const void *buffer, size_t buffer_size, uintptr_t base_address,
                                const IPCompiledPattern *compiled,
                                const size_t *bucket_offsets,
                                const size_t *bucket_counts,
                                const size_t *ordered_indices,
                                size_t pattern_count,
                                IPScanResult *results) {
    if (!buffer || buffer_size == 0) return;

    ip_scan_all_wildcard_patterns(base_address, buffer_size, compiled, pattern_count, results);

    for (size_t bucket = 0; bucket < 256; bucket++) {
        if (bucket_counts[bucket] == 0) continue;
        ip_scan_bucketed_buffer(buffer, buffer_size, base_address, compiled,
                                ordered_indices + bucket_offsets[bucket],
                                bucket_counts[bucket], results);
    }
}

static void ip_scan_image_many(const struct mach_header *mh, intptr_t slide,
                               const IPCompiledPattern *compiled,
                               const size_t *bucket_offsets,
                               const size_t *bucket_counts,
                               const size_t *ordered_indices,
                               size_t pattern_count,
                               IPScanResult *results) {
    size_t header_size = 0;
    bool is_64 = false;

    if (mh->magic == MH_MAGIC_64) {
        header_size = sizeof(struct mach_header_64);
        is_64 = true;
    } else if (mh->magic == MH_MAGIC) {
        header_size = sizeof(struct mach_header);
    } else {
        return;
    }

    const uint8_t *lc_ptr = (const uint8_t *)mh + header_size;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)lc_ptr;

        if (is_64 && lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc_ptr;
            if (!((seg->initprot | seg->maxprot) & VM_PROT_EXECUTE)) {
                lc_ptr += lc->cmdsize;
                continue;
            }

            const struct section_64 *section =
                (const struct section_64 *)(seg + 1);
            bool scanned_section = false;

            for (uint32_t sec = 0; sec < seg->nsects; sec++, section++) {
                if (!ip_section_has_instructions_64(section) || section->size == 0) continue;
                scanned_section = true;
                uintptr_t address = (uintptr_t)(section->addr + slide);
                ip_scan_region_many((const void *)address, (size_t)section->size, address,
                                    compiled, bucket_offsets, bucket_counts,
                                    ordered_indices, pattern_count, results);
            }

            if (!scanned_section && seg->vmsize != 0) {
                uintptr_t address = (uintptr_t)(seg->vmaddr + slide);
                ip_scan_region_many((const void *)address, (size_t)seg->vmsize, address,
                                    compiled, bucket_offsets, bucket_counts,
                                    ordered_indices, pattern_count, results);
            }
        } else if (!is_64 && lc->cmd == LC_SEGMENT) {
            const struct segment_command *seg = (const struct segment_command *)lc_ptr;
            if (!((seg->initprot | seg->maxprot) & VM_PROT_EXECUTE)) {
                lc_ptr += lc->cmdsize;
                continue;
            }

            const struct section *section = (const struct section *)(seg + 1);
            bool scanned_section = false;

            for (uint32_t sec = 0; sec < seg->nsects; sec++, section++) {
                if (!ip_section_has_instructions_32(section) || section->size == 0) continue;
                scanned_section = true;
                uintptr_t address = (uintptr_t)(section->addr + slide);
                ip_scan_region_many((const void *)address, (size_t)section->size, address,
                                    compiled, bucket_offsets, bucket_counts,
                                    ordered_indices, pattern_count, results);
            }

            if (!scanned_section && seg->vmsize != 0) {
                uintptr_t address = (uintptr_t)(seg->vmaddr + slide);
                ip_scan_region_many((const void *)address, (size_t)seg->vmsize, address,
                                    compiled, bucket_offsets, bucket_counts,
                                    ordered_indices, pattern_count, results);
            }
        }

        lc_ptr += lc->cmdsize;
    }
}

void ip_scan_main_executable_many(const IPPattern *patterns, size_t pattern_count,
                                  IPScanResult *results) {
    if (!results) return;
    memset(results, 0, pattern_count * sizeof(*results));

    if (!patterns || pattern_count == 0) return;

    IPCompiledPattern *compiled = calloc(pattern_count, sizeof(*compiled));
    size_t *ordered_indices = calloc(pattern_count, sizeof(*ordered_indices));
    if (!compiled || !ordered_indices) {
        free(compiled);
        free(ordered_indices);
        return;
    }

    size_t bucket_counts[256] = {0};
    size_t bucket_offsets[256] = {0};

    for (size_t i = 0; i < pattern_count; i++) {
        if (!ip_compile_pattern(&patterns[i], &compiled[i])) continue;
        if (compiled[i].has_anchor) {
            bucket_counts[compiled[i].anchor_byte]++;
        }
    }

    size_t running = 0;
    for (size_t i = 0; i < 256; i++) {
        bucket_offsets[i] = running;
        running += bucket_counts[i];
    }

    size_t bucket_fills[256];
    memcpy(bucket_fills, bucket_offsets, sizeof(bucket_fills));

    for (size_t i = 0; i < pattern_count; i++) {
        if (!compiled[i].has_anchor) continue;
        size_t bucket = compiled[i].anchor_byte;
        ordered_indices[bucket_fills[bucket]++] = i;
    }

    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; i++) {
        const struct mach_header *mh = _dyld_get_image_header(i);
        if (!mh || mh->filetype != MH_EXECUTE) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        ip_scan_image_many(mh, slide, compiled, bucket_offsets, bucket_counts,
                           ordered_indices, pattern_count, results);
        break;
    }

    free(ordered_indices);
    free(compiled);
}

IPScanResult ip_scan_main_executable(const IPPattern *pattern) {
    IPScanResult result = { .count = 0 };
    if (!pattern || pattern->length == 0) return result;

    ip_scan_main_executable_many(pattern, 1, &result);
    return result;
}

// ---------------------------------------------------------------------------
// Process memory scan — walk all readable+executable regions (slow fallback)
// ---------------------------------------------------------------------------

IPScanResult ip_scan_process(const IPPattern *pattern) {
    IPScanResult combined = { .count = 0 };
    if (!pattern || pattern->length == 0) return combined;

    IPCompiledPattern compiled;
    if (!ip_compile_pattern(pattern, &compiled)) return combined;

    mach_port_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    natural_t depth = 1;

    while (combined.count < IP_MAX_MATCHES) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(task, &addr, &size, &depth,
                                                (vm_region_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) {
            depth++;
            continue;
        }

        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_EXECUTE)) {
            IPScanResult region = ip_scan_compiled_buffer((const void *)addr, (size_t)size,
                                                          (uintptr_t)addr, &compiled);
            for (size_t i = 0; i < region.count && combined.count < IP_MAX_MATCHES; i++) {
                combined.addresses[combined.count++] = region.addresses[i];
            }
        }

        addr += size;
    }

    return combined;
}
