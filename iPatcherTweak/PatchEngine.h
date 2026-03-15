#import <Foundation/Foundation.h>

@interface IPPatchEngine : NSObject

+ (instancetype)sharedEngine;

/// Scan process memory and apply all enabled patches for the given bundle ID.
/// Returns the number of successful patch applications.
- (NSInteger)applyPatchesForBundleID:(NSString *)bundleID;

@end
