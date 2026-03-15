#import <Foundation/Foundation.h>

@interface IPMemoryUtils : NSObject

/// Patch memory at a given address: temporarily makes it writable, copies bytes,
/// restores protection, and flushes the instruction cache.
+ (BOOL)patchMemoryAtAddress:(uintptr_t)address
                   withBytes:(const uint8_t *)bytes
                      length:(size_t)length;

@end
