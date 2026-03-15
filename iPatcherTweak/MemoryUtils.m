#import "MemoryUtils.h"
#import "DebugLog.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <libkern/OSCacheControl.h>
#import <string.h>

@implementation IPMemoryUtils

+ (BOOL)patchMemoryAtAddress:(uintptr_t)address
                   withBytes:(const uint8_t *)bytes
                      length:(size_t)length {
    if (!bytes || length == 0) return NO;

    mach_port_t task = mach_task_self();

    // Page-align the range
    uintptr_t page_start = address & ~(uintptr_t)0xFFF;
    uintptr_t page_end   = (address + length + 0xFFF) & ~(uintptr_t)0xFFF;
    vm_size_t region_len  = (vm_size_t)(page_end - page_start);

    // Query current protection
    vm_address_t query_addr = (vm_address_t)page_start;
    vm_size_t    query_size = 0;
    natural_t    depth      = 1;
    struct vm_region_submap_info_64 info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

    kern_return_t kr = vm_region_recurse_64(
        task, &query_addr, &query_size, &depth,
        (vm_region_info_t)&info, &count
    );
    if (kr != KERN_SUCCESS) {
        NSLog(@"[iPatcher] vm_region_recurse_64 failed: %s", mach_error_string(kr));
        IPDebugLog(@"[iPatcher] vm_region_recurse_64 failed for 0x%lx: %s",
                   (unsigned long)address, mach_error_string(kr));
        return NO;
    }

    vm_prot_t orig_prot = info.protection;

    // Make writable (keep read+execute, add write+copy)
    kr = vm_protect(task, (vm_address_t)page_start, region_len,
                    FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[iPatcher] vm_protect (write) failed: %s", mach_error_string(kr));
        IPDebugLog(@"[iPatcher] vm_protect(write) failed for 0x%lx len=%lu: %s",
                   (unsigned long)address, (unsigned long)length, mach_error_string(kr));
        return NO;
    }

    // Write the patch
    memcpy((void *)address, bytes, length);

    // Restore original protection
    vm_protect(task, (vm_address_t)page_start, region_len, FALSE, orig_prot);

    // Flush instruction cache so CPU picks up the new bytes
    sys_icache_invalidate((void *)address, length);
    IPDebugLog(@"[iPatcher] Wrote %lu byte(s) at 0x%lx",
               (unsigned long)length, (unsigned long)address);

    return YES;
}

@end
