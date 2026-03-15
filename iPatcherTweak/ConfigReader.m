#import "ConfigReader.h"
#import "DebugLog.h"
#import "../Shared/iPatcherConstants.h"

@implementation IPConfigReader

+ (instancetype)sharedReader {
    static IPConfigReader *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IPConfigReader alloc] init];
    });
    return instance;
}

- (NSArray<NSDictionary *> *)patchesForBundleID:(NSString *)bundleID {
    NSString *dir  = @IP_PATCHES_PATH;
    NSString *file = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.json", bundleID]];

    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data) {
        IPDebugLog(@"%@ No profile found for %@ at %@", @IP_LOG_PREFIX, bundleID, file);
        return @[];
    }

    NSError *error = nil;
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:data
                                                            options:0
                                                              error:&error];
    if (error || ![profile isKindOfClass:[NSDictionary class]]) {
        NSLog(@IP_LOG_PREFIX " Failed to parse config for %@: %@", bundleID, error);
        IPDebugLog(@"%@ Failed to parse config for %@ at %@: %@",
                   @IP_LOG_PREFIX, bundleID, file, error);
        return @[];
    }

    // Profile-level kill switch
    if (![profile[@"enabled"] boolValue]) {
        IPDebugLog(@"%@ Profile disabled for %@", @IP_LOG_PREFIX, bundleID);
        return @[];
    }

    NSArray<NSDictionary *> *patches = profile[@"patches"] ?: @[];
    IPDebugLog(@"%@ Loaded profile for %@ with %lu patch(es) from %@",
               @IP_LOG_PREFIX, bundleID, (unsigned long)patches.count, file);

    return patches;
}

@end
