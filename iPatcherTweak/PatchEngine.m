#import "PatchEngine.h"
#import "PatternScanner.h"
#import "MemoryUtils.h"
#import "ConfigReader.h"
#import "DebugLog.h"
#import "../Shared/iPatcherConstants.h"

@interface IPPreparedPatch : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) IPPattern pattern;
@property (nonatomic, assign) IPPattern replacement;
@property (nonatomic, assign) NSInteger offset;
@end

@implementation IPPreparedPatch
@end

@implementation IPPatchEngine

+ (instancetype)sharedEngine {
    static IPPatchEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IPPatchEngine alloc] init];
    });
    return instance;
}

- (NSInteger)applyPatchesForBundleID:(NSString *)bundleID {
    NSArray *patches = [[IPConfigReader sharedReader] patchesForBundleID:bundleID];
    if (!patches.count) {
        IPDebugLog(@"%@ No enabled patches for %@", @IP_LOG_PREFIX, bundleID);
        return 0;
    }

    NSLog(@IP_LOG_PREFIX " Processing %lu patches for %@",
          (unsigned long)patches.count, bundleID);
    IPDebugLog(@"%@ Processing %lu patch(es) for %@",
               @IP_LOG_PREFIX, (unsigned long)patches.count, bundleID);

    NSMutableArray<IPPreparedPatch *> *prepared = [NSMutableArray arrayWithCapacity:patches.count];

    for (NSDictionary *patch in patches) {
        if (![patch[@"enabled"] boolValue]) continue;

        NSString *patternStr     = patch[@"pattern"];
        NSString *replacementStr = patch[@"replacement"];
        NSNumber *offsetNum      = patch[@"offset"];
        NSString *patchName      = patch[@"name"] ?: @"unnamed";
        NSInteger offset         = offsetNum ? [offsetNum integerValue] : 0;

        if (!patternStr.length || !replacementStr.length) {
            NSLog(@IP_LOG_PREFIX " Skipping '%@': missing pattern or replacement", patchName);
            IPDebugLog(@"%@ Skipping '%@' for %@: missing pattern or replacement",
                       @IP_LOG_PREFIX, patchName, bundleID);
            continue;
        }

        IPPattern pattern;
        if (!ip_pattern_parse([patternStr UTF8String], &pattern)) {
            NSLog(@IP_LOG_PREFIX " Failed to parse pattern for '%@'", patchName);
            IPDebugLog(@"%@ Failed to parse pattern for '%@' in %@",
                       @IP_LOG_PREFIX, patchName, bundleID);
            continue;
        }

        IPPattern replacement;
        if (!ip_pattern_parse([replacementStr UTF8String], &replacement)) {
            NSLog(@IP_LOG_PREFIX " Failed to parse replacement for '%@'", patchName);
            IPDebugLog(@"%@ Failed to parse replacement for '%@' in %@",
                       @IP_LOG_PREFIX, patchName, bundleID);
            continue;
        }

        IPPreparedPatch *entry = [[IPPreparedPatch alloc] init];
        entry.name = patchName;
        entry.pattern = pattern;
        entry.replacement = replacement;
        entry.offset = offset;
        [prepared addObject:entry];
    }

    if (!prepared.count) {
        IPDebugLog(@"%@ No valid patch definitions remained for %@", @IP_LOG_PREFIX, bundleID);
        return 0;
    }

    IPPattern *patterns = calloc(prepared.count, sizeof(*patterns));
    IPScanResult *results = calloc(prepared.count, sizeof(*results));
    if (!patterns || !results) {
        free(patterns);
        free(results);
        NSLog(@IP_LOG_PREFIX " Failed to allocate scan buffers for %@", bundleID);
        IPDebugLog(@"%@ Failed to allocate scan buffers for %@", @IP_LOG_PREFIX, bundleID);
        return 0;
    }

    for (NSUInteger idx = 0; idx < prepared.count; idx++) {
        patterns[idx] = prepared[idx].pattern;
    }

    ip_scan_main_executable_many(patterns, prepared.count, results);

    NSInteger applied = 0;

    for (NSUInteger idx = 0; idx < prepared.count; idx++) {
        IPPreparedPatch *patch = prepared[idx];
        IPScanResult result = results[idx];
        NSLog(@IP_LOG_PREFIX " '%@': %zu match(es)", patch.name, result.count);
        IPDebugLog(@"%@ '%@' for %@ matched %zu location(s)",
                   @IP_LOG_PREFIX, patch.name, bundleID, result.count);

        for (size_t i = 0; i < result.count; i++) {
            uintptr_t target = result.addresses[i] + (uintptr_t)patch.offset;

            if ([IPMemoryUtils patchMemoryAtAddress:target
                                          withBytes:patch.replacement.bytes
                                             length:patch.replacement.length]) {
                applied++;
                NSLog(@IP_LOG_PREFIX " Patched '%@' at 0x%lx", patch.name, (unsigned long)target);
                IPDebugLog(@"%@ Patched '%@' for %@ at 0x%lx",
                           @IP_LOG_PREFIX, patch.name, bundleID, (unsigned long)target);
            } else {
                NSLog(@IP_LOG_PREFIX " FAILED to patch '%@' at 0x%lx", patch.name, (unsigned long)target);
                IPDebugLog(@"%@ Failed to patch '%@' for %@ at 0x%lx",
                           @IP_LOG_PREFIX, patch.name, bundleID, (unsigned long)target);
            }
        }
    }

    free(results);
    free(patterns);

    return applied;
}

@end
