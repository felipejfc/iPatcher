#import <Foundation/Foundation.h>
#import "PatchEngine.h"
#import "DebugLog.h"
#import "../Shared/iPatcherConstants.h"

__attribute__((constructor))
static void iPatcherInit(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleID) {
            IPDebugLog(@"%@ Constructor ran without a bundle identifier", @IP_LOG_PREFIX);
            return;
        }

        // Never patch ourselves
        if ([bundleID isEqualToString:@IP_BUNDLE_ID]) {
            IPDebugLog(@"%@ Skipping self for %@", @IP_LOG_PREFIX, bundleID);
            return;
        }

        NSLog(@IP_LOG_PREFIX " Loaded into %@", bundleID);
        IPDebugLog(@"%@ Loaded into %@", @IP_LOG_PREFIX, bundleID);

        NSInteger count = [[IPPatchEngine sharedEngine] applyPatchesForBundleID:bundleID];
        if (count > 0) {
            NSLog(@IP_LOG_PREFIX " Successfully applied %ld patch(es) to %@",
                  (long)count, bundleID);
        }
        IPDebugLog(@"%@ Finished for %@ with %ld applied patch(es)",
                   @IP_LOG_PREFIX, bundleID, (long)count);
    }
}
