#import <Foundation/Foundation.h>

@interface IPConfigReader : NSObject

+ (instancetype)sharedReader;

/// Returns an array of patch dictionaries for the given bundle ID, or empty array.
/// Each dict has: name, pattern, replacement, offset, enabled
- (NSArray<NSDictionary *> *)patchesForBundleID:(NSString *)bundleID;

@end
